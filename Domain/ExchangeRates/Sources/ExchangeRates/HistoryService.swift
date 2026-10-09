import Foundation

/// Loads and caches fiat or cryptocurrency history.
public actor HistoryService {
  private let client: any HTTPClient
  private let directory: URL
  private static let euroAssets: Set<String> = [
    "AAVE", "ADA", "ALGO", "ATOM", "AVAX", "BCH", "BTC", "DOGE", "DOT", "ETC", "ETH",
    "FIL", "ICP", "LINK", "LTC", "SHIB", "SOL", "UNI", "USDC", "USDT", "XLM", "XRP"
  ]
  private static let dollarAssets = euroAssets.subtracting(["USDC"])
  private static let sterlingAssets = euroAssets.subtracting(["AVAX", "ICP", "XLM", "XRP"])

  /// Whether a distinct, crypto-first pair has direct hourly candles or two supported quote legs.
  public static func supportsIntraday(base: String, quote: String) -> Bool {
    intradayCandleQuote(base: base, quote: quote) != nil
  }

  private static func intradayCandleQuote(base: String, quote: String) -> String? {
    guard base != quote else { return nil }
    if CurrencyCatalog.crypto.contains(quote) {
      if dollarAssets.contains(base) && dollarAssets.contains(quote) { return "USD" }
      return euroAssets.contains(base) && euroAssets.contains(quote) ? "EUR" : nil
    }
    return switch quote {
    case "USD": dollarAssets.contains(base) ? quote : nil
    case "EUR": euroAssets.contains(base) ? quote : nil
    case "GBP": sterlingAssets.contains(base) ? quote : nil
    default: nil
    }
  }
  /// The provider capabilities configured by the host.
  public nonisolated let policy: RateProviderPolicy

  /// Whether the configured providers can supply hourly observations for this pair.
  public nonisolated func supportsIntraday(base: String, quote: String) -> Bool {
    policy == .coinbaseEnhanced && Self.supportsIntraday(base: base, quote: quote)
  }

  /// Creates a history service, defaulting to Fawaz daily history.
  public init(
    directory: URL, client: any HTTPClient = NetworkClient(timeout: 30),
    policy: RateProviderPolicy = .daily
  ) {
    self.directory = directory
    self.client = client
    self.policy = policy
  }

  /// Loads Fawaz daily history, or completed Coinbase hourly candles for an enabled day chart.
  /// All-history requests sample available daily publications at each month end, starting
  /// with the Fawaz archive in March 2024. Failed requests return only compatible saved series.
  public func load(
    base: String, quote: String, range: HistoryRange, now: Date = .now,
    cacheLifetime: TimeInterval? = nil
  ) async -> HistoryResult {
    await loadSeries(base: base, quote: quote, range: range, now: now, cacheLifetime: cacheLifetime)
  }

  private func loadSeries(
    base: String, quote: String, range: HistoryRange, now: Date,
    cacheLifetime: TimeInterval?
  ) async -> HistoryResult {
    guard CurrencyCatalog.codes.contains(base), CurrencyCatalog.codes.contains(quote),
      base != quote
    else { return HistoryResult(series: nil, issue: .unsupportedPair) }
    let intradayQuote = Self.intradayCandleQuote(base: base, quote: quote)
    guard range != .day || supportsIntraday(base: base, quote: quote) else {
      return HistoryResult(series: nil, issue: .intradayUnavailable)
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let year = calendar.component(.year, from: now)
    let interval = range == .yearToDate ? "\(range.rawValue)-\(year)" : "\(range.rawValue)"
    let file = directory.appendingPathComponent(
      "history-\(policy.rawValue)-\(range == .day ? "coinbase" : "fawaz")-\(base)-\(quote)-\(interval).json"
    )
    let cached = (try? Data(contentsOf: file))
      .flatMap { try? JSONDecoder().decode(HistorySeries.self, from: $0) }
      .flatMap { series -> HistorySeries? in
        let expected = range == .day ? RateProviderID.coinbase : .fawaz
        let observation: RateObservation =
          range == .day ? .hourlyClose : range == .all ? .monthlyReference : .dailyReference
        guard series.source.provider == expected, series.source.observation == observation,
          series.source.latestObservation == nil, series.points.count >= 2,
          series.points.allSatisfy({ $0.value.isFinite && $0.value > 0 && $0.date <= now }),
          series.fetchedAt <= now
        else { return nil }
        guard range == .yearToDate else { return series }
        guard calendar.component(.year, from: series.fetchedAt) == year,
          series.points.allSatisfy({ calendar.component(.year, from: $0.date) == year })
        else { return nil }
        return series
      }
    let defaultCacheLifetime: TimeInterval = range == .day ? 3600 : (range == .all ? 86400 : 21600)
    if let cached, now >= cached.fetchedAt,
      now.timeIntervalSince(cached.fetchedAt) < (cacheLifetime ?? defaultCacheLifetime),
      range != .day || now < Self.nextHour(after: cached.fetchedAt)
    {
      return HistoryResult(series: cached, issue: nil)
    }
    do {
      let start: Date
      if range == .all {
        guard
          let beginning = calendar.date(
            from: DateComponents(year: 2024, month: 3, day: 2))
        else { throw RateError.invalidData }
        start = beginning
      } else if range == .year {
        guard let beginning = calendar.date(byAdding: .year, value: -1, to: now) else {
          throw RateError.invalidData
        }
        start = beginning
      } else if range == .yearToDate {
        guard let beginning = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        else { throw RateError.invalidData }
        start = beginning
      } else {
        start = now.addingTimeInterval(-Double(range.rawValue) * 86400)
      }
      let points: [HistoryPoint]
      if range == .day {
        guard let candleQuote = intradayQuote else { throw RateError.invalidData }
        let candles = try await Self.fetchCryptoHistory(
          client: client, code: base, quote: candleQuote, start: start, end: now,
          granularity: .hour)
        if CurrencyCatalog.crypto.contains(quote) {
          let quoteCandles = try await Self.fetchCryptoHistory(
            client: client, code: quote, quote: candleQuote, start: start, end: now,
            granularity: .hour)
          points = try Self.divideAlignedCloses(candles, by: quoteCandles)
        } else {
          points = candles
        }
      } else {
        points = try await Self.fetchDailyHistory(
          client: client, directory: directory, base: base, quote: quote,
          start: start, now: now, monthly: range == .all)
      }
      try Task.checkCancellation()
      guard points.count >= 2 else { throw RateError.unavailable }
      let source = RateSource(
        provider: range == .day ? .coinbase : .fawaz,
        observation: range == .day
          ? .hourlyClose : range == .all ? .monthlyReference : .dailyReference,
        timeZone: .gmt)
      let series = HistorySeries(points: points, source: source, fetchedAt: now)
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(series).write(to: file, options: .atomic)
      } catch {
        return HistoryResult(
          series: series, issue: .cacheWriteFailed)
      }
      return HistoryResult(series: series, issue: nil)
    } catch {
      return HistoryResult(
        series: cached,
        issue: cached == nil
          ? .unavailable
          : .usingCachedSeries)
    }
  }

  /// The next UTC boundary at which a completed hourly observation may become available.
  public static func nextHour(after date: Date) -> Date {
    Date(timeIntervalSince1970: (floor(date.timeIntervalSince1970 / 3600) + 1) * 3600)
  }

  private static func fetchCryptoHistory(
    client: any HTTPClient, code: String, quote: String = "USD", start: Date, end: Date,
    granularity: CandleGranularity
  ) async throws -> [HistoryPoint] {
    guard
      let components = URLComponents(
        string: "https://api.exchange.coinbase.com/products/\(code)-\(quote)/candles")
    else { throw RateError.invalidData }
    let combined = try await fetchCandles(
      client: client, components: components, start: start, end: end,
      granularity: granularity)
    return combined.map { HistoryPoint(date: $0.key, value: $0.value) }
      .sorted { $0.date < $1.date }
  }

}
