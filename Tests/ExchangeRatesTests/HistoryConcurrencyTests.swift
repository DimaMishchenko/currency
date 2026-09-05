import Foundation
import Testing

@testable import ExchangeRates

private actor SlowCandles: HTTPClient {
  private(set) var active = 0
  private(set) var maximum = 0
  private(set) var calls = 0
  let delay: Duration
  init(delay: Duration = .milliseconds(400)) { self.delay = delay }

  func get(_ url: URL) async throws -> Data {
    calls += 1
    active += 1
    maximum = max(maximum, active)
    defer { active -= 1 }
    try await Task.sleep(for: delay)
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
  @Test func pagesOverlapWithinBoundAndBoundaryOwnershipIsDeterministic() async throws {
    let client = SlowCandles()
    let start = Date(timeIntervalSince1970: 0)
    let end = start.addingTimeInterval(1200 * 86400)
    let components = try #require(URLComponents(string: "https://example.test/candles"))
    let points = try await HistoryService.fetchCandles(
      client: client, components: components, start: start, end: end)
    #expect(await client.calls == 5)
    #expect(await client.maximum > 1)
    #expect(await client.maximum <= 3)
    #expect(points.count == 10)
    #expect(!points.values.contains(99))
    #expect(points[start.addingTimeInterval(299 * 86400)] == 3)
  }

  @Test func cancellingHistoryStopsPagesAndDoesNotWriteCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = SlowCandles(delay: .seconds(10))
    let service = HistoryService(directory: directory, client: client)
    let task = Task { await service.load(base: "BTC", quote: "USD", range: .all) }
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
