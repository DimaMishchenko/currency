import Foundation

/// Shared by history loaders in this process, including when users switch charts.
private actor CandlePacer {
  static let shared = CandlePacer()
  private let clock = ContinuousClock()
  private var lastStart: ContinuousClock.Instant?

  func acquire() async throws {
    while let lastStart, clock.now < lastStart.advanced(by: .milliseconds(150)) {
      try await clock.sleep(until: lastStart.advanced(by: .milliseconds(150)))
    }
    try Task.checkCancellation()
    lastStart = clock.now
  }
}

extension HistoryService {
  /// Overlaps up to three pages while spacing request starts below the public rate limit.
  /// Structured cancellation prevents a failed or cancelled load from saving partial history.
  static func fetchCandles(
    client: any HTTPClient, components: URLComponents, start: Date, end: Date
  ) async throws -> [Date: Double] {
    let windows = candleWindows(start: start, end: end)
    return try await withThrowingTaskGroup(of: [HistoryPoint].self) { group in
      func enqueue(_ window: (start: Date, end: Date)) {
        group.addTask {
          try await CandlePacer.shared.acquire()
          var request = components
          request.queryItems = [
            URLQueryItem(name: "granularity", value: "86400"),
            URLQueryItem(name: "start", value: window.start.ISO8601Format()),
            URLQueryItem(name: "end", value: window.end.ISO8601Format())
          ]
          guard let url = request.url else { throw RateError.invalidData }
          let data = try await client.get(url)
          try Task.checkCancellation()
          // Half-open page ranges give each candle one owner regardless of completion order.
          return try decodeCandles(data, start: window.start, end: end)
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
