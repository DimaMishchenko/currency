import Foundation

/// A dated historical conversion value.
public struct HistoryPoint: Codable, Sendable, Identifiable, Equatable {
  /// The date used as the stable identity.
  public var id: Date { date }
  /// The quote date.
  public let date: Date
  /// The historical conversion value.
  public let value: Double
}
/// A cached historical time series.
public struct HistorySeries: Codable, Sendable {
  /// The ordered history points.
  public let points: [HistoryPoint]
  /// The provider and aggregation description.
  public let source: String
  /// The time at which the series was fetched.
  public let fetchedAt: Date
}
/// The result of loading a historical series.
public struct HistoryResult: Sendable {
  /// The loaded or cached series.
  public let series: HistorySeries?
  /// A user-facing availability or cache message.
  public let message: String?
}
/// Loads and caches fiat or cryptocurrency history.
public actor HistoryService {
  private let client: any HTTPClient
  private let directory: URL
  /// Creates a history service with a cache directory and HTTP client.
  public init(directory: URL, client: any HTTPClient = NetworkClient(timeout: 30)) {
    self.directory = directory; self.client = client
  }
  /// Loads a supported historical range, falling back to a saved series when needed.
  public func load(base: String, quote: String, days: Int, now: Date = .now) async -> HistoryResult
  {
    // Zero denotes all available provider history, not a zero-day interval.
    guard Currency.codes.contains(base), Currency.codes.contains(quote),
      [7, 30, 90, 365, 0].contains(days), base != quote
    else { return HistoryResult(series: nil, message: "History is unavailable for this pair.") }
    let file = directory.appendingPathComponent("history-\(base)-\(quote)-\(days).json")
    let cached = (try? Data(contentsOf: file))
      .flatMap { try? JSONDecoder().decode(HistorySeries.self, from: $0) }
    if let cached, now.timeIntervalSince(cached.fetchedAt) < (days == 0 ? 86400 : 21600) {
      return HistoryResult(series: cached, message: nil)
    }
    do {
      let isCrypto = Currency.crypto.contains(base)
      var calendar = Calendar(identifier: .gregorian)
      guard let utc = TimeZone(secondsFromGMT: 0) else { throw RateError.invalidData }
      calendar.timeZone = utc
      let start: Date
      if days == 0 {
        guard
          let beginning = calendar.date(
            from: DateComponents(year: isCrypto ? 2009 : 1948, month: 1, day: 1))
        else { throw RateError.invalidData }
        start = beginning
      } else if days == 365 {
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
        var combined: [Date: Double] = [:]
        for window in Self.candleWindows(start: start, end: now) {
          try Task.checkCancellation()
          components.queryItems = [
            URLQueryItem(name: "granularity", value: "86400"),
            URLQueryItem(name: "start", value: window.start.ISO8601Format()),
            URLQueryItem(name: "end", value: window.end.ISO8601Format())
          ]
          guard let url = components.url else { throw RateError.invalidData }
          let data = try await client.get(url)
          for point in try Self.decodeCandles(data, start: window.start, end: now)
          where point.date <= window.end {
            combined[point.date] = point.value
          }
          if window.end < now { try await Task.sleep(for: .milliseconds(150)) }
        }
        let daily = combined.map { HistoryPoint(date: $0.key, value: $0.value) }
          .sorted { $0.date < $1.date }
        points = days == 0 ? Self.monthlyCloses(daily) : daily
      } else {
        components.queryItems = [
          URLQueryItem(name: "base", value: base), URLQueryItem(name: "quotes", value: quote),
          URLQueryItem(name: "from", value: String(start.ISO8601Format().prefix(10))),
          URLQueryItem(name: "to", value: String(now.ISO8601Format().prefix(10)))
        ]
        if days == 0 { components.queryItems?.append(URLQueryItem(name: "group", value: "month")) }
        guard let url = components.url else { throw RateError.invalidData }
        let data = try await client.get(url)
        points = try Self.decodeFiat(data, base: base, quote: quote)
      }
      guard points.count >= 2 else { throw RateError.unavailable }
      let source =
        isCrypto
        ? (days == 0
          ? "Coinbase · monthly last available close · UTC" : "Coinbase · daily closes · UTC")
        : (days == 0
          ? "Frankfurter · monthly reference rates" : "Frankfurter · daily reference rates")
      let series = HistorySeries(points: points, source: source, fetchedAt: now)
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(series).write(to: file, options: .atomic)
      } catch {
        return HistoryResult(
          series: series, message: "History loaded, but couldn’t be saved offline.")
      }
      return HistoryResult(series: series, message: nil)
    } catch {
      return HistoryResult(
        series: cached,
        message: cached == nil
          ? "History is unavailable. Your converter still works with saved rates."
          : "Can’t update history. Showing the saved chart.")
    }
  }
  static func candleWindows(start: Date, end: Date) -> [(start: Date, end: Date)] {
    var windows: [(Date, Date)] = []
    var cursor = start
    // 299 days leaves room for Coinbase's inclusive boundary candle (300 maximum).
    while cursor < end {
      let next = min(cursor.addingTimeInterval(299 * 86400), end)
      windows.append((cursor, next)); cursor = next
    }
    return windows
  }
  static func monthlyCloses(_ points: [HistoryPoint]) -> [HistoryPoint] {
    var calendar = Calendar(identifier: .gregorian);
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    var months: [Date: HistoryPoint] = [:]
    for point in points.sorted(by: { $0.date < $1.date }) {
      if let month = calendar.dateInterval(of: .month, for: point.date)?.start {
        months[month] = point
      }
    }
    return months.values.sorted { $0.date < $1.date }
  }
  /// Decodes Frankfurter history rows into chronological points.
  public static func decodeFiat(_ data: Data, base: String, quote: String) throws -> [HistoryPoint]
  {
    let rows = try JSONDecoder().decode([FrankfurterRow].self, from: data)
    var values: [Date: Double] = [:]
    for row in rows {
      guard row.base == base, row.quote == quote, validDate(row.date), row.rate > 0,
        !row.rate.isNaN,
        let date = ISO8601DateFormatter().date(from: row.date + "T00:00:00Z")
      else { throw RateError.invalidData }
      let value = NSDecimalNumber(decimal: row.rate).doubleValue
      guard value.isFinite else { throw RateError.invalidData }
      values[date] = value
    }
    return values.map { HistoryPoint(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
  }
  /// Decodes completed Coinbase candles within a date range.
  public static func decodeCandles(_ data: Data, start: Date, end: Date) throws -> [HistoryPoint] {
    let rows = try JSONDecoder().decode([[Double]].self, from: data)
    var values: [Date: Double] = [:]
    for row in rows {
      guard row.count >= 5, row.allSatisfy(\.isFinite), row[4] > 0 else {
        throw RateError.invalidData
      }
      let date = Date(timeIntervalSince1970: row[0])
      // Exclude unfinished daily candles and any extra buckets before the requested range.
      if date >= start && date.addingTimeInterval(86400) <= end { values[date] = row[4] }
    }
    return values.map { HistoryPoint(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
  }
}
