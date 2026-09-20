import Foundation

extension HistoryService {
  static func candleWindows(start: Date, end: Date) -> [(start: Date, end: Date)] {
    var windows: [(Date, Date)] = []
    var cursor = start
    // 299 days leaves room for Coinbase's inclusive boundary candle (300 maximum).
    while cursor < end {
      let next = min(cursor.addingTimeInterval(299 * 86400), end)
      windows.append((cursor, next))
      cursor = next
    }
    return windows
  }

  static func monthlyCloses(_ points: [HistoryPoint]) -> [HistoryPoint] {
    var calendar = Calendar(identifier: .gregorian)

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
  static func decodeFiat(_ data: Data, base: String, quote: String) throws -> [HistoryPoint] {
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
  static func decodeCandles(_ data: Data, start: Date, end: Date) throws -> [HistoryPoint] {
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
