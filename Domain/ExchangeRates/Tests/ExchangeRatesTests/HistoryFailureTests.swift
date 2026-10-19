import Foundation
import Testing

@testable import ExchangeRates

@Suite struct HistoryFailureTests {
  @Test func failedWeeklyRefreshPreservesChartAndRecordsHourlyAttempt() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DailyHistoryHTTP()
    let now = try historyDate("2026-01-08T12:00:00Z")
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: "BTC", quote: "USD", range: .week, now: now)
    let file = directory.appendingPathComponent("history-v3-BTC-USD-7.json")
    let original = try JSONDecoder().decode(HistoryCacheRecord.self, from: Data(contentsOf: file))
    await client.failRequests()
    let failed = await service.load(
      base: "BTC", quote: "USD", range: .week,
      now: now.addingTimeInterval(86400))
    #expect(failed.series?.points == first.series?.points)
    #expect(failed.issue == .usingCachedSeries)
    let saved = try JSONDecoder().decode(HistoryCacheRecord.self, from: Data(contentsOf: file))
    #expect(saved.series.points == original.series.points)
    #expect(saved.series.source == original.series.source)
    #expect(saved.series.fetchedAt == original.series.fetchedAt)
    #expect(saved.weeklyHourlyAttemptedAt == now.addingTimeInterval(86400))
  }

  @Test(arguments: [
    RateProviderID.frankfurter, .custom("Example feed")
  ])
  func incompatibleCacheNeverReturnsFreshOrOffline(provider: RateProviderID) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = try historyDate("2026-01-08T12:00:00Z")
    let saved = HistorySeries(
      points: [
        .init(date: now.addingTimeInterval(-86400), value: 2), .init(date: now, value: 3)
      ], source: .init(provider: provider, observation: .dailyReference), fetchedAt: now)
    let data = try JSONEncoder().encode(saved)
    try data.write(to: directory.appendingPathComponent("history-v3-BTC-USD-7.json"))
    let client = DailyHistoryHTTP()
    await client.failRequests()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "USD", range: .week, now: now)
    #expect(result.series == nil)
    #expect(result.issue == .unavailable)
    #expect(await !client.urls.isEmpty)
  }

}
