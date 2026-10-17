import Foundation
import Testing

@testable import ExchangeRates

private actor GatedHistoryWriteHTTP: HTTPClient {
  let fallback: Bool
  let rate: Double
  let blocked: Bool
  private var started = false
  private var released = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var requests = 0
  let daily = DailyHistoryHTTP()

  init(fallback: Bool = false, rate: Double = 4, blocked: Bool = false) {
    self.fallback = fallback
    self.rate = rate
    self.blocked = blocked
  }

  func get(_ url: URL) async throws -> Data {
    requests += 1
    started = true
    startWaiters.forEach { $0.resume() }
    startWaiters.removeAll()
    if blocked && !released {
      await withCheckedContinuation { releaseWaiters.append($0) }
    }
    guard url.host == "api.frankfurter.dev" else { return try await daily.get(url) }
    if fallback { throw RateError.http(503) }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    let from = query.first { $0.name == "from" }!.value!
    let to = query.first { $0.name == "to" }!.value!
    return Data(
      "[{\"date\":\"\(from)\",\"base\":\"EUR\",\"quote\":\"USD\",\"rate\":\(rate)},{\"date\":\"\(to)\",\"base\":\"EUR\",\"quote\":\"USD\",\"rate\":\(rate)}]"
        .utf8)
  }

  func waitUntilStarted() async {
    if !started { await withCheckedContinuation { startWaiters.append($0) } }
  }

  func release() {
    released = true
    releaseWaiters.forEach { $0.resume() }
    releaseWaiters.removeAll()
  }
}

@Suite struct HistoryCacheWriteTests {
  let now = Date(timeIntervalSince1970: 1_792_065_600)

  private func file(in directory: URL) -> URL {
    directory.appendingPathComponent("history-v3-USD-EUR-30.json")
  }

  private func saved(
    at date: Date, value: Double = 0.5, provider: RateProviderID = .frankfurter
  ) -> HistorySeries {
    HistorySeries(
      points: [
        .init(date: date.addingTimeInterval(-86400), value: value),
        .init(date: date, value: value)
      ], source: .init(provider: provider, observation: .dailyReference, timeZone: .gmt),
      fetchedAt: date)
  }

  private func save(_ series: HistorySeries, in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(HistoryCacheRecord(series: series)).write(to: file(in: directory))
  }

  private func expectSelected(
    _ expected: HistorySeries?, result: HistoryResult, directory: URL, at date: Date
  ) async throws {
    #expect(result.issue == nil)
    #expect(result.series?.points == expected?.points)
    #expect(result.series?.source == expected?.source)
    #expect(result.series?.fetchedAt == expected?.fetchedAt)
    let disk = try JSONDecoder()
      .decode(HistoryCacheRecord.self, from: Data(contentsOf: file(in: directory)))
    #expect(disk.series.points == expected?.points)
    #expect(disk.series.source == expected?.source)
    #expect(disk.series.fetchedAt == expected?.fetchedAt)
    let offline = GatedHistoryWriteHTTP(fallback: true)
    let next = await HistoryService(directory: directory, client: offline)
      .load(base: "USD", quote: "EUR", range: .month, now: date)
    #expect(next.issue == nil)
    #expect(next.series?.points == expected?.points)
    #expect(next.series?.source == expected?.source)
    #expect(next.series?.fetchedAt == expected?.fetchedAt)
    #expect(await offline.requests == 0)
  }

  @Test(arguments: [false, true])
  func slowerFallbackRetainsPreferredSuccess(stale: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    if stale {
      try save(saved(at: now.addingTimeInterval(-86400), provider: .fawaz), in: directory)
    }
    let blocked = GatedHistoryWriteHTTP(fallback: true, blocked: true)
    let slow = HistoryService(directory: directory, client: blocked)
    let pending = Task { await slow.load(base: "USD", quote: "EUR", range: .month, now: now) }
    await blocked.waitUntilStarted()
    let preferred = await HistoryService(directory: directory, client: GatedHistoryWriteHTTP())
      .load(base: "USD", quote: "EUR", range: .month, now: now)
    await blocked.release()
    let result = await pending.value
    #expect(preferred.series?.source.provider == .frankfurter)
    try await expectSelected(preferred.series, result: result, directory: directory, at: now)
  }

  @Test func olderSuccessRetainsNewerSuccess() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let blocked = GatedHistoryWriteHTTP(rate: 2, blocked: true)
    let slow = HistoryService(directory: directory, client: blocked)
    let pending = Task { await slow.load(base: "USD", quote: "EUR", range: .month, now: now) }
    await blocked.waitUntilStarted()
    let later = now.addingTimeInterval(60)
    let newer = await HistoryService(directory: directory, client: GatedHistoryWriteHTTP(rate: 4))
      .load(base: "USD", quote: "EUR", range: .month, now: later)
    await blocked.release()
    try await expectSelected(
      newer.series, result: await pending.value, directory: directory, at: later)
  }

  @Test(arguments: ["invalid", "stale", "lifetime"])
  func successfulFallbackReplacesUnusableConcurrentPreferred(change: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let blocked = GatedHistoryWriteHTTP(fallback: true, blocked: true)
    let slow = HistoryService(directory: directory, client: blocked)
    let lifetime: TimeInterval? = change == "lifetime" ? 30 : nil
    let pending = Task {
      await slow.load(base: "USD", quote: "EUR", range: .month, now: now, cacheLifetime: lifetime)
    }
    await blocked.waitUntilStarted()
    let date = now.addingTimeInterval(change == "stale" ? -21600 : -60)
    try save(saved(at: date, value: change == "invalid" ? -1 : 0.25), in: directory)
    await blocked.release()
    let result = await pending.value
    #expect(result.series?.source.provider == .fawaz)
    #expect(result.series?.fetchedAt == now)
    try await expectSelected(result.series, result: result, directory: directory, at: now)
  }

  @Test func completedMonthExtensionReplacesBundledFrankfurterSource() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("history-v3-USD-EUR-0.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let points = [
      HistoryPoint(date: try historyDate("2026-07-31T00:00:00Z"), value: 0.5),
      HistoryPoint(date: try historyDate("2026-08-31T00:00:00Z"), value: 0.6)
    ]
    let current = HistorySeries(
      points: points, source: .init(provider: .frankfurter, observation: .monthlyReference),
      fetchedAt: now)
    try JSONEncoder().encode(HistoryCacheRecord(series: current)).write(to: file)
    let extended = HistorySeries(
      points: points + [.init(date: try historyDate("2026-09-30T00:00:00Z"), value: 0.7)],
      source: .init(provider: .fawaz, observation: .monthlyReference), fetchedAt: now)
    #expect(HistoryService.validHistory(current, base: "USD", quote: "EUR", range: .all, now: now))
    #expect(HistoryService.validHistory(extended, base: "USD", quote: "EUR", range: .all, now: now))
    let selected = try HistoryService.recordSuccessfulRefresh(
      at: file, series: extended, base: "USD", quote: "EUR", range: .all,
      now: now, cacheLifetime: nil, fiatPolicy: false)
    #expect(selected.points == extended.points)
    #expect(selected.source == extended.source)
    let disk = try JSONDecoder().decode(HistoryCacheRecord.self, from: Data(contentsOf: file))
    #expect(disk.series.points == extended.points)
    #expect(disk.series.source == extended.source)
  }

  @Test func intradayFreshnessExpiresAtNextHourEvenWithLongLifetime() throws {
    let fetched = try historyDate("2026-10-15T11:59:00Z")
    let points = (0...288)
      .map { offset in
        HistoryPoint(date: fetched.addingTimeInterval(Double(offset - 288) * 300), value: 100)
      }
    let series = HistorySeries(
      points: points, source: .init(provider: .coinMetrics, observation: .minuteReference),
      fetchedAt: fetched)
    let boundary = try historyDate("2026-10-15T12:00:00Z")
    #expect(
      HistoryService.validHistory(series, base: "BTC", quote: "USD", range: .day, now: boundary))
    #expect(
      HistoryService.freshHistory(
        series, range: .day, now: boundary.addingTimeInterval(-1), cacheLifetime: 86400))
    #expect(
      !HistoryService.freshHistory(
        series, range: .day, now: boundary, cacheLifetime: 86400))
  }

}
