import Foundation

extension HistoryService {
  static func dailyDates(start: Date, now: Date, monthly: Bool) -> [Date] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    guard let archiveStart = calendar.date(from: DateComponents(year: 2024, month: 3, day: 2))
    else { return [] }
    let end = calendar.startOfDay(for: now)
    var cursor = max(calendar.startOfDay(for: start), archiveStart)
    var dates: [Date] = []
    while cursor <= end {
      if monthly {
        guard let month = calendar.dateInterval(of: .month, for: cursor) else { break }
        dates.append(min(month.end.addingTimeInterval(-86400), end))
        cursor = month.end
      } else {
        dates.append(cursor)
        cursor = cursor.addingTimeInterval(86400)
      }
    }
    return dates
  }

  static func fetchDailyHistory(
    client: any HTTPClient, directory: URL, base: String, quote: String,
    start: Date, now: Date, monthly: Bool
  ) async throws -> [HistoryPoint] {
    let dates = dailyDates(start: start, now: now, monthly: monthly)
    return try await withThrowingTaskGroup(of: HistoryPoint?.self) { group in
      func enqueue(_ date: Date) {
        group.addTask {
          try Task.checkCancellation()
          let day = String(date.ISO8601Format().prefix(10))
          let quotes = try await dailySnapshot(client: client, directory: directory, day: day)
          guard let a = quotes[base]?.value, let b = quotes[quote]?.value else { return nil }
          let value = NSDecimalNumber(decimal: b / a).doubleValue
          guard value.isFinite && value > 0 else { throw RateError.invalidData }
          return HistoryPoint(date: date, value: value)
        }
      }
      var next = 0
      while next < min(3, dates.count) {
        enqueue(dates[next])
        next += 1
      }
      var points: [HistoryPoint] = []
      while let point = try await group.next() {
        if let point { points.append(point) }
        try Task.checkCancellation()
        if next < dates.count {
          enqueue(dates[next])
          next += 1
        }
      }
      return points.sorted { $0.date < $1.date }
    }
  }

  private static func dailySnapshot(
    client: any HTTPClient, directory: URL, day: String
  ) async throws -> [String: ExchangeRate] {
    let archive = directory.appendingPathComponent("fawaz-daily-v1", isDirectory: true)
    let file = archive.appendingPathComponent("\(day).json")
    func decode(_ data: Data) throws -> [String: ExchangeRate] {
      let quotes = try FawazProvider.decode(data)
      guard quotes.values.allSatisfy({ $0.published == day }) else { throw RateError.invalidData }
      return quotes
    }
    if let saved = try? Data(contentsOf: file), let quotes = try? decode(saved) { return quotes }
    var missingEndpoints = 0
    for endpoint in [
      "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@\(day)/v1/currencies/eur.min.json",
      "https://\(day).currency-api.pages.dev/v1/currencies/eur.min.json"
    ] {
      try Task.checkCancellation()
      guard let url = URL(string: endpoint) else { throw RateError.invalidData }
      do {
        let data = try await client.get(url)
        let quotes = try decode(data)
        try Task.checkCancellation()
        try? FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return quotes
      } catch {
        if case RateError.http(404) = error { missingEndpoints += 1 }
        try Task.checkCancellation()
      }
    }
    if missingEndpoints == 2 { return [:] }
    throw RateError.unavailable
  }
}
