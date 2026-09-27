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
  /// Fiat pairs use Frankfurter reference rates; crypto bases require a USD quote and use
  /// completed Coinbase hourly (`.day`) or daily candles. `.all` aggregates observations by month.
  /// Fiat intraday history is unavailable. No current
  /// FX rate is applied to historical crypto prices. Failed pagination never saves partial data.
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
    guard range != .day || isCrypto else {
      return HistoryResult(series: nil, issue: .intradayUnavailable)
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let year = calendar.component(.year, from: now)
    // A YTD cache belongs to one calendar year, including when a refresh fails at rollover.
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
      guard
        var components = URLComponents(
          string: isCrypto
            ? "https://api.exchange.coinbase.com/products/\(base)-\(quote)/candles"
            : "https://api.frankfurter.dev/v2/rates")
      else { throw RateError.invalidData }
      let points: [HistoryPoint]
      if isCrypto {
        guard quote == "USD" else { throw RateError.unavailable }
        let granularity: CandleGranularity = range == .day ? .hour : .day
        let end = range == .day ? now : calendar.startOfDay(for: now)
        let combined = try await Self.fetchCandles(
          client: client, components: components,
          start: range == .day ? start : calendar.startOfDay(for: start), end: end,
          granularity: granularity)
        let candles = combined.map { HistoryPoint(date: $0.key, value: $0.value) }
          .sorted { $0.date < $1.date }
        points = range == .all ? Self.monthlyCloses(candles) : candles
      } else {
        components.queryItems = [
          URLQueryItem(name: "base", value: base), URLQueryItem(name: "quotes", value: quote),
          URLQueryItem(name: "from", value: String(start.ISO8601Format().prefix(10))),
          URLQueryItem(name: "to", value: String(now.ISO8601Format().prefix(10)))
        ]
        if range == .all {
          components.queryItems?.append(URLQueryItem(name: "group", value: "month"))
        }
        guard let url = components.url else { throw RateError.invalidData }
        let data = try await client.get(url)
        let references = try Self.decodeFiat(data, base: base, quote: quote)
        points =
          range == .yearToDate
          ? references.filter { $0.date >= start && $0.date <= now } : references
      }
      try Task.checkCancellation()
      guard points.count >= 2 else { throw RateError.unavailable }
      let source = RateSource(
        provider: isCrypto ? .coinbase : .frankfurter,
        observation: isCrypto
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
}
