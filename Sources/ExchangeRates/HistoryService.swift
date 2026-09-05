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
  /// completed Coinbase daily candles. `.all` aggregates observations by month. No current
  /// FX rate is applied to historical crypto prices. Failed pagination never saves partial data.
  /// - Parameters:
  ///   - base: Uppercase currency whose historical value is requested.
  ///   - quote: Uppercase denomination of the returned values.
  ///   - range: Requested historical interval.
  ///   - now: Evaluation time for date windows and cache freshness; injectable for tests.
  /// - Returns: A series and an optional recoverable issue. Cancellation returns the saved
  ///   series if available; callers should check cancellation before presenting the result.
  public func load(
    base: String, quote: String, range: HistoryRange, now: Date = .now
  ) async -> HistoryResult {
    let days = range.rawValue
    // Zero denotes all available provider history, not a zero-day interval.
    guard CurrencyCatalog.codes.contains(base), CurrencyCatalog.codes.contains(quote),
      base != quote
    else { return HistoryResult(series: nil, issue: .unsupportedPair) }
    let file = directory.appendingPathComponent("history-\(base)-\(quote)-\(days).json")
    let cached = (try? Data(contentsOf: file))
      .flatMap { try? JSONDecoder().decode(HistorySeries.self, from: $0) }
    if let cached, now >= cached.fetchedAt,
      now.timeIntervalSince(cached.fetchedAt) < (range == .all ? 86400 : 21600)
    {
      return HistoryResult(series: cached, issue: nil)
    }
    do {
      let isCrypto = CurrencyCatalog.crypto.contains(base)
      var calendar = Calendar(identifier: .gregorian)
      guard let utc = TimeZone(secondsFromGMT: 0) else { throw RateError.invalidData }
      calendar.timeZone = utc
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
      } else {
        start = now.addingTimeInterval(-Double(days) * 86400)
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
        let end = calendar.startOfDay(for: now)
        let combined = try await Self.fetchCandles(
          client: client, components: components,
          start: calendar.startOfDay(for: start), end: end)
        let daily = combined.map { HistoryPoint(date: $0.key, value: $0.value) }
          .sorted { $0.date < $1.date }
        points = range == .all ? Self.monthlyCloses(daily) : daily
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
        points = try Self.decodeFiat(data, base: base, quote: quote)
      }
      try Task.checkCancellation()
      guard points.count >= 2 else { throw RateError.unavailable }
      let source = RateSource(
        provider: isCrypto ? .coinbase : .frankfurter,
        observation: isCrypto
          ? (range == .all ? .monthlyLastClose : .dailyClose)
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
