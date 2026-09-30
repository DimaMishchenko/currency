import Foundation

enum CandleGranularity: Int, Sendable {
  case hour = 3600
  case day = 86400
}

extension HistoryService {
  static func fetchCandles(
    client: any HTTPClient, components: URLComponents, start: Date, end: Date,
    granularity: CandleGranularity = .day
  ) async throws -> [Date: Double] {
    let windows = candleWindows(start: start, end: end, granularity: granularity)
    return try await withThrowingTaskGroup(of: [HistoryPoint].self) { group in
      func enqueue(_ window: (start: Date, end: Date)) {
        group.addTask {
          try Task.checkCancellation()
          var request = components
          request.queryItems = [
            URLQueryItem(name: "granularity", value: String(granularity.rawValue)),
            URLQueryItem(name: "start", value: window.start.ISO8601Format()),
            URLQueryItem(name: "end", value: window.end.ISO8601Format())
          ]
          guard let url = request.url else { throw RateError.invalidData }
          let data = try await client.get(url)
          try Task.checkCancellation()
          return try decodeCandles(
            data, start: window.start, end: end, granularity: granularity
          )
          .filter { $0.date < window.end }
        }
      }
      var next = 0
      while next < min(3, windows.count) {
        enqueue(windows[next])
        next += 1
      }
      var combined: [Date: Double] = [:]
      while let points = try await group.next() {
        for point in points { combined[point.date] = point.value }
        try Task.checkCancellation()
        if next < windows.count {
          enqueue(windows[next])
          next += 1
        }
      }
      return combined
    }
  }
}
