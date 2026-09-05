import Foundation
import Testing

@testable import ExchangeRates

private actor FailingPageClient: HTTPClient {
  private(set) var calls = 0
  func get(_ url: URL) async throws -> Data {
    calls += 1
    guard calls == 1 else { throw RateError.http(429) }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    let raw = try #require(query?.first(where: { $0.name == "start" })?.value)
    let start = try #require(ISO8601DateFormatter().date(from: raw)).timeIntervalSince1970
    return try JSONEncoder()
      .encode([
        [start + 86400, 1, 5, 2, 3, 1], [start + 172800, 1, 5, 2, 4, 1]
      ])
  }
}

@Suite struct HistoryFailureTests {
  @Test func failedPaginationDoesNotSaveAnIncompleteChart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = FailingPageClient()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "USD", range: .year)
    #expect(await client.calls == 2)
    #expect(result.series == nil)
    #expect(result.issue == .unavailable)
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("history-BTC-USD-365.json").path))
  }
  @Test func failedPaginationPreservesExistingChart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("history-BTC-USD-365.json")
    let saved = HistorySeries(
      points: [HistoryPoint(date: .distantPast, value: 5)],
      source: .init(provider: .custom("saved")), fetchedAt: .distantPast)
    let original = try JSONEncoder().encode(saved)
    try original.write(to: file)
    let result = await HistoryService(directory: directory, client: FailingPageClient())
      .load(base: "BTC", quote: "USD", range: .year)
    #expect(result.series?.points == saved.points)
    #expect(result.issue == .usingCachedSeries)
    #expect(try Data(contentsOf: file) == original)
  }
}
