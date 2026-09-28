import Foundation

/// Loads and caches fiat or cryptocurrency history.
public actor HistoryService {
  private let client: any HTTPClient
  private let directory: URL
  /// Creates a history service with a cache directory and HTTP client.
  public init(directory: URL, client: any HTTPClient = NetworkClient(timeout: 30)) {
    self.directory = directory
    self.client = client
  }

  /// Loads a series, reusing a fresh cache or returning saved history when a request fails.
  ///
  /// Pairs without crypto use Frankfurter reference rates. Crypto/USD uses completed Coinbase
  /// hourly (`.day`) or daily candles. Crypto/crypto divides matching Coinbase USD closes;
  /// crypto/fiat or crypto/metal multiplies Coinbase USD closes by Frankfurter USD/quote
  /// references on matching UTC dates. `.all` samples the joined history by month.
  /// Frankfurter-based intraday history is unavailable. Failed pagination saves no partial data.
  /// - Parameters:
  ///   - base: Uppercase currency whose historical value is requested.
  ///   - quote: Uppercase denomination of the returned values.
  ///   - range: Requested historical interval.
  ///   - now: Evaluation time for date windows and cache freshness; injectable for tests.
  ///   - cacheLifetime: Optional caller cadence; nil keeps the one-hour (`.day`), six-hour,
  ///     or daily (`.all`) policy.
  /// - Returns: A series and an optional recoverable issue. Cancellation returns the saved
  ///   series if available; callers should check cancellation before presenting the result.
  public func load(
    base: String, quote: String, range: HistoryRange, now: Date = .now,
    cacheLifetime: TimeInterval? = nil
  ) async -> HistoryResult {
    guard CurrencyCatalog.codes.contains(base), CurrencyCatalog.codes.contains(quote),
      base != quote
    else { return HistoryResult(series: nil, issue: .unsupportedPair) }
    let isCrypto = CurrencyCatalog.crypto.contains(base)
    let quoteIsCrypto = CurrencyCatalog.crypto.contains(quote)
    let needsReference = isCrypto && quote != "USD" && !quoteIsCrypto
    guard range != .day || (isCrypto && !needsReference) else {
      return HistoryResult(series: nil, issue: .intradayUnavailable)
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let year = calendar.component(.year, from: now)
    let interval = range == .yearToDate ? "\(range.rawValue)-\(year)" : "\(range.rawValue)"
    let file = directory.appendingPathComponent("history-\(base)-\(quote)-\(interval).json")
    let cached = (try? Data(contentsOf: file))
      .flatMap { try? JSONDecoder().decode(HistorySeries.self, from: $0) }
      .flatMap { series -> HistorySeries? in
        guard range == .yearToDate else { return series }
        guard calendar.component(.year, from: series.fetchedAt) == year,
          series.points.allSatisfy({ calendar.component(.year, from: $0.date) == year })
        else { return nil }
        return series
      }
    let defaultCacheLifetime: TimeInterval = range == .day ? 3600 : (range == .all ? 86400 : 21600)
    if let cached, now >= cached.fetchedAt,
      now.timeIntervalSince(cached.fetchedAt) < (cacheLifetime ?? defaultCacheLifetime)
    {
      return HistoryResult(series: cached, issue: nil)
    }
    do {
      let start: Date
      if range == .all {
        guard
          let beginning = calendar.date(
            from: DateComponents(year: isCrypto ? 2009 : 1948, month: 1, day: 1))
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
      if isCrypto {
        let references =
          needsReference
          ? try await Self.fetchFiatHistory(
            client: client, base: "USD", quote: quote, start: start, now: now)
          : []
        let granularity: CandleGranularity = range == .day ? .hour : .day
        let end = range == .day ? now : calendar.startOfDay(for: now)
        let candles = try await Self.fetchCryptoHistory(
          client: client, code: base,
          start: range == .day ? start : calendar.startOfDay(for: start), end: end,
          granularity: granularity)
        let combined: [HistoryPoint]
        if quoteIsCrypto {
          let quoteCandles = try await Self.fetchCryptoHistory(
            client: client, code: quote,
            start: range == .day ? start : calendar.startOfDay(for: start), end: end,
            granularity: granularity)
          combined = try Self.divideAlignedCloses(candles, by: quoteCandles)
        } else if needsReference {
          combined = try Self.convertDailyCloses(candles, rates: references)
        } else {
          combined = candles
        }
        points = range == .all ? Self.monthlyCloses(combined) : combined
      } else {
        let references = try await Self.fetchFiatHistory(
          client: client, base: base, quote: quote, start: start, now: now,
          monthly: range == .all)
        points =
          range == .yearToDate
          ? references.filter { $0.date >= start && $0.date <= now } : references
      }
      try Task.checkCancellation()
      guard points.count >= 2 else { throw RateError.unavailable }
      let source = RateSource(
        provider: needsReference
          ? .custom("Coinbase + Frankfurter") : isCrypto ? .coinbase : .frankfurter,
        observation: needsReference
          ? .unspecified
          : isCrypto
            ? (range == .all ? .monthlyLastClose : (range == .day ? .hourlyClose : .dailyClose))
            : (range == .all ? .monthlyReference : .dailyReference),
        timeZone: isCrypto ? .gmt : nil
      )
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

  private static func fetchCryptoHistory(
    client: any HTTPClient, code: String, start: Date, end: Date,
    granularity: CandleGranularity
  ) async throws -> [HistoryPoint] {
    guard
      let components = URLComponents(
        string: "https://api.exchange.coinbase.com/products/\(code)-USD/candles")
    else { throw RateError.invalidData }
    let combined = try await fetchCandles(
      client: client, components: components, start: start, end: end,
      granularity: granularity)
    return combined.map { HistoryPoint(date: $0.key, value: $0.value) }
      .sorted { $0.date < $1.date }
  }

  private static func fetchFiatHistory(
    client: any HTTPClient, base: String, quote: String, start: Date, now: Date,
    monthly: Bool = false
  ) async throws -> [HistoryPoint] {
    guard var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates")
    else { throw RateError.invalidData }
    components.queryItems = [
      URLQueryItem(name: "base", value: base), URLQueryItem(name: "quotes", value: quote),
      URLQueryItem(name: "from", value: String(start.ISO8601Format().prefix(10))),
      URLQueryItem(name: "to", value: String(now.ISO8601Format().prefix(10)))
    ]
    if monthly {
      components.queryItems?.append(URLQueryItem(name: "group", value: "month"))
    }
    guard let url = components.url else { throw RateError.invalidData }
    let data = try await client.get(url)
    return try decodeFiat(data, base: base, quote: quote)
  }
}
