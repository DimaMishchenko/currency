import Foundation
import Testing

@testable import ExchangeRates

private actor BudgetHTTP: HTTPClient {
  private(set) var starts: [Date] = []
  let limited: Bool
  init(limited: Bool = false) { self.limited = limited }
  func get(_ url: URL) async throws -> Data {
    starts.append(.now)
    if limited { throw RateError.rateLimited(retryAfter: Date.now.addingTimeInterval(30)) }
    return Data(#"{"data":[]}"#.utf8)
  }
}

@Suite struct CoinMetricsBudgetTests {
  @Test func separateSharedClientsRespectOneSecondStartSpacing() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let http = BudgetHTTP()
    let now = Date.now
    async let first = CoinMetricsClient(client: http, directory: directory)
      .observations(assets: ["btc"], start: now.addingTimeInterval(-60), end: now)
    async let second = CoinMetricsClient(client: http, directory: directory)
      .observations(assets: ["eth"], start: now.addingTimeInterval(-60), end: now)
    _ = try await (first, second)
    let times = await http.starts.sorted()
    #expect(times.count == 2)
    #expect(times[1].timeIntervalSince(times[0]) >= 0.99)
  }

  @Test func rateLimitCooldownSurvivesCallerCancellationAndNewClient() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let http = BudgetHTTP(limited: true)
    let now = Date.now
    let first = Task {
      try await CoinMetricsClient(client: http, directory: directory)
        .observations(assets: ["btc"], start: now.addingTimeInterval(-60), end: now)
    }
    let stateURL = directory.appendingPathComponent("coin-metrics-budget.json")
    var recorded: CoinMetricsBudget.State?
    for _ in 0..<100 {
      recorded = (try? Data(contentsOf: stateURL))
        .flatMap {
          try? JSONDecoder().decode(CoinMetricsBudget.State.self, from: $0)
        }
      if (recorded?.cooldown ?? .distantPast) > now { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect((recorded?.cooldown.timeIntervalSince(now) ?? 0) >= 30)
    first.cancel()
    await #expect(throws: CancellationError.self) { try await first.value }
    let second = Task {
      try await CoinMetricsClient(client: http, directory: directory)
        .observations(assets: ["eth"], start: now.addingTimeInterval(-60), end: now)
    }
    try await Task.sleep(for: .milliseconds(150))
    second.cancel()
    await #expect(throws: CancellationError.self) { try await second.value }
    #expect(await http.starts.count == 1)
  }

  @Test func expiredRequestLeaseRecoversButCorruptBudgetFailsClosed() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("coin-metrics-budget.json")
    let state = CoinMetricsBudget.State(lease: .init(owner: UUID(), expires: .distantPast))
    try JSONEncoder().encode(state).write(to: url)
    let http = BudgetHTTP()
    let now = Date.now
    _ = try await CoinMetricsClient(client: http, directory: directory)
      .observations(assets: ["btc"], start: now.addingTimeInterval(-60), end: now)
    try Data("corrupt".utf8).write(to: url)
    await #expect(throws: (any Error).self) {
      try await CoinMetricsClient(client: http, directory: directory)
        .observations(assets: ["eth"], start: now.addingTimeInterval(-60), end: now)
    }
    #expect(await http.starts.count == 1)
  }

  @Test func retryHeadersRespectLaterOfSecondsHTTPDateAndReset() throws {
    let now = Date(timeIntervalSince1970: 1_767_355_200)
    let url = try #require(URL(string: "https://example.test"))
    func response(_ headers: [String: String]) throws -> HTTPURLResponse {
      try #require(
        HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headers))
    }
    #expect(
      try HTTPTransport.retryAfter(response(["Retry-After": "12"]), now: now)
        == now.addingTimeInterval(12))
    #expect(
      try HTTPTransport.retryAfter(
        response(["Retry-After": "Fri, 02 Jan 2026 12:00:30 GMT"]), now: now)
        == now.addingTimeInterval(30))
    #expect(
      try HTTPTransport.retryAfter(
        response(["Retry-After": "12", "X-RateLimit-Reset": "1767355245"]), now: now)
        == now.addingTimeInterval(45))
    #expect(
      try HTTPTransport.retryAfter(
        response(["Retry-After": "invalid", "X-RateLimit-Reset": "NaN"]), now: now) == nil)
  }
}
