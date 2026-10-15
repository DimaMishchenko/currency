import Foundation
import Testing

@testable import ExchangeRates

private actor SlowCandles: HTTPClient {
  private(set) var active = 0
  private(set) var maximum = 0
  private(set) var calls = 0
  private let delay: Duration?
  private var firstRequest: CheckedContinuation<Void, Never>?

  init(delay: Duration? = nil) { self.delay = delay }

  func get(_ url: URL) async throws -> Data {
    calls += 1
    let call = calls
    active += 1
    maximum = max(maximum, active)
    defer { active -= 1 }
    if let delay {
      try await Task.sleep(for: delay)
    } else if call == 1 {
      await withCheckedContinuation { firstRequest = $0 }
    } else if call == 2 {
      firstRequest?.resume()
      firstRequest = nil
    }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    let startString = try #require(query?.first { $0.name == "start" }?.value)
    let endString = try #require(query?.first { $0.name == "end" }?.value)
    let start = try #require(ISO8601DateFormatter().date(from: startString)).timeIntervalSince1970
    let end = try #require(ISO8601DateFormatter().date(from: endString)).timeIntervalSince1970
    return try JSONEncoder()
      .encode([
        [start, 1, 5, 2, 3, 1], [start + 86400, 1, 5, 2, 4, 1],
        [end, 1, 5, 2, 99, 1]
      ])
  }
}

@Suite struct HistoryConcurrencyTests {
  @Test func cancellingHistoryStopsPagesAndDoesNotWriteCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = SlowCandles(delay: .seconds(10))
    let service = HistoryService(directory: directory, client: client)
    let task = Task { await service.load(base: "BTC", quote: "USD", range: .year) }
    for _ in 0..<300 {
      if await client.active > 0 { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await client.active > 0)
    task.cancel()
    let result = await task.value
    #expect(result.series == nil)
    #expect(await client.active == 0)
    #expect(await client.calls <= 3)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }
}
