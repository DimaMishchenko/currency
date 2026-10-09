import Foundation

extension HistoryService {
  static func candleWindows(
    start: Date, end: Date, granularity: CandleGranularity = .day
  ) -> [(start: Date, end: Date)] {
    var windows: [(Date, Date)] = []
    var cursor = start
    // 299 buckets leaves room for Coinbase's inclusive boundary candle (300 maximum).
    while cursor < end {
      let next = min(cursor.addingTimeInterval(299 * Double(granularity.rawValue)), end)
      windows.append((cursor, next))
      cursor = next
    }
    return windows
  }

  static func divideAlignedCloses(
    _ base: [HistoryPoint], by quote: [HistoryPoint]
  ) throws -> [HistoryPoint] {
    let quotesByDate = Dictionary(uniqueKeysWithValues: quote.map { ($0.date, $0.value) })
    return try base.compactMap { point in
      guard let quote = quotesByDate[point.date] else { return nil }
      let value = point.value / quote
      guard value.isFinite && value > 0 else { throw RateError.invalidData }
      return HistoryPoint(date: point.date, value: value)
    }
  }

  static func decodeCandles(
    _ data: Data, start: Date, end: Date, granularity: CandleGranularity = .day
  ) throws -> [HistoryPoint] {
    let rows = try JSONDecoder().decode([[Double]].self, from: data)
    var values: [Date: Double] = [:]
    for row in rows {
      guard row.count >= 5, row.allSatisfy(\.isFinite), row[4] > 0 else {
        throw RateError.invalidData
      }
      let date = Date(timeIntervalSince1970: row[0])
      if date >= start && date.addingTimeInterval(Double(granularity.rawValue)) <= end {
        values[date] = row[4]
      }
    }
    return values.map { HistoryPoint(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
  }
}
