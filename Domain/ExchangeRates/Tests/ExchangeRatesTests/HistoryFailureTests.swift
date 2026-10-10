import Foundation
import Testing

@testable import ExchangeRates

@Suite struct HistoryFailureTests {
  @Test func failedDailyRequestPreservesOnlyCompatibleCompleteChart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DailyHistoryHTTP()
    let now = try historyDate("2026-01-08T12:00:00Z")
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: "BTC", quote: "USD", range: .week, now: now)
    let file = directory.appendingPathComponent("history-daily-fawaz-BTC-USD-7.json")
    let original = try Data(contentsOf: file)
    await client.failRequests()
    let failed = await service.load(
      base: "BTC", quote: "USD", range: .week,
      now: now.addingTimeInterval(86400))
    #expect(failed.series?.points == first.series?.points)
    #expect(failed.issue == .usingCachedSeries)
    #expect(try Data(contentsOf: file) == original)
  }

  @Test(arguments: [RateProviderID.coinbase, .frankfurter, .custom("Coinbase + Frankfurter")])
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
    try data.write(to: directory.appendingPathComponent("history-daily-fawaz-BTC-USD-7.json"))
    try data.write(to: directory.appendingPathComponent("history-BTC-USD-7.json"))
    let client = DailyHistoryHTTP()
    await client.failRequests()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "USD", range: .week, now: now)
    #expect(result.series == nil)
    #expect(result.issue == .unavailable)
    #expect(await !client.urls.isEmpty)
  }

  @Test func policyModeSeparatesSeriesCachesAndDisabledHourlyNeverReadsSavedCoinbase() async throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try historyDate("2026-01-08T12:00:00Z")
    let client = DailyHistoryHTTP()
    let enhanced = HistoryService(directory: directory, client: client, policy: .coinbaseEnhanced)
    #expect(enhanced.supportsIntraday(base: "BTC", quote: "USD"))
    _ = await enhanced.load(base: "BTC", quote: "USD", range: .week, now: now)
    let daily = HistoryService(directory: directory, client: client)
    #expect(!daily.supportsIntraday(base: "BTC", quote: "USD"))
    _ = await daily.load(base: "BTC", quote: "USD", range: .week, now: now)
    let before = await client.urls.count
    let saved = HistorySeries(
      points: [
        .init(date: now.addingTimeInterval(-7200), value: 2),
        .init(date: now.addingTimeInterval(-3600), value: 3)
      ],
      source: .init(provider: .coinbase, observation: .hourlyClose, timeZone: .gmt), fetchedAt: now)
    try JSONEncoder().encode(saved)
      .write(
        to: directory.appendingPathComponent("history-coinbaseEnhanced-coinbase-BTC-USD-1.json"))
    let result = await daily.load(base: "BTC", quote: "USD", range: .day, now: now)
    #expect(result.series == nil)
    #expect(result.issue == .intradayUnavailable)
    #expect(await client.urls.count == before)
    for mode in ["daily", "coinbaseEnhanced"] {
      #expect(
        FileManager.default.fileExists(
          atPath:
            directory.appendingPathComponent("history-\(mode)-fawaz-BTC-USD-7.json").path))
    }
  }
}
