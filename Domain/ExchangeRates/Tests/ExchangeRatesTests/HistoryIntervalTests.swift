import Foundation
import Testing

@testable import ExchangeRates

@Suite struct HistoryIntervalTests {
  @Test(arguments: Array(CurrencyCatalog.crypto))
  func allCatalogCryptoSupportFiatAndCryptoIntraday(code: String) {
    #expect(HistoryService.supportsIntraday(base: code, quote: "USD"))
    #expect(HistoryService.supportsIntraday(base: code, quote: "CZK"))
    if code != "BTC" { #expect(HistoryService.supportsIntraday(base: code, quote: "BTC")) }
  }

  @Test(arguments: [("USD", "EUR"), ("BTC", "XAU"), ("XAG", "BTC"), ("BTC", "BTC")])
  func unsupportedPairsDoNotRequest(base: String, quote: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let client = MinuteHistoryHTTP()
    let result = await HistoryService(
      directory: directory, client: client
    )
    .load(base: base, quote: quote, range: .day)
    #expect(result.series == nil)
    #expect(result.issue == (base == quote ? .unsupportedPair : .intradayUnavailable))
    #expect(await client.urls.isEmpty)
  }

  @Test func halfHourCacheExpiryPreservesOfflineSeries() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try historyDate("2026-01-05T00:00:00Z")
    let client = MinuteHistoryHTTP()
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: "BTC", quote: "USD", range: .day, now: now)
    #expect(first.issue == nil)
    await client.fail()
    let fresh = await service.load(
      base: "BTC", quote: "USD", range: .day, now: now.addingTimeInterval(1799))
    #expect(fresh.issue == nil)
    #expect(await client.urls.count == 1)
    let stale = await service.load(
      base: "BTC", quote: "USD", range: .day, now: now.addingTimeInterval(1800))
    #expect(stale.issue == .usingCachedSeries)
    #expect(stale.series?.points == first.series?.points)
    #expect(await client.urls.count == 2)
  }

  @Test func fractionalFetchTimeReusesFullWindowAndPreservesItWhenOffline() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try historyDate("2026-01-05T00:05:17Z")
    let endpoint = try historyDate("2026-01-05T00:05:00Z")
    let client = MinuteHistoryHTTP()
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: "BTC", quote: "USD", range: .day, now: now)
    let series = try #require(first.series)
    #expect(first.issue == nil)
    #expect(series.fetchedAt == now)
    #expect(series.points.first?.date == endpoint.addingTimeInterval(-86400))
    #expect(series.points.count == 288)
    await client.fail()
    let fresh = await service.load(
      base: "BTC", quote: "USD", range: .day, now: now.addingTimeInterval(1799))
    #expect(fresh.issue == nil)
    #expect(fresh.series?.points == series.points)
    #expect(fresh.series?.fetchedAt == now)
    #expect(await client.urls.count == 1)
    let expired = await service.load(
      base: "BTC", quote: "USD", range: .day, now: now.addingTimeInterval(1800))
    #expect(expired.issue == .usingCachedSeries)
    #expect(expired.series?.points == series.points)
    #expect(expired.series?.fetchedAt == now)
    #expect(await client.urls.count == 2)
  }

  @Test func coverageRejectsLargeInteriorGapsAndShortenedWindows() {
    let end = Date(timeIntervalSince1970: 86400)
    let full = (0..<288)
      .map { HistoryPoint(date: Date(timeIntervalSince1970: Double($0) * 300), value: 1) }
    #expect(HistoryService.coversDay(full, ending: end))
    #expect(!HistoryService.coversDay(Array(full.suffix(7)), ending: end))
    #expect(
      !HistoryService.coversDay(
        full.filter {
          $0.date.timeIntervalSince1970 < 3600 || $0.date.timeIntervalSince1970 > 7200
        }, ending: end))
  }
}

@Suite struct BundledHistoryTests {
  @Test func historicalCryptoNeverPredatesObservedCoverage() throws {
    let now = try historyDate("2026-01-05T00:00:00Z")
    let btc = try BundledHistory.points(base: "BTC", quote: "USD", through: now)
    #expect(!btc.isEmpty)
    #expect(btc.first!.date >= (try historyDate("2010-07-18T00:00:00Z")))
    #expect(btc.last!.date < (try historyDate("2024-03-01T00:00:00Z")))
    #expect(try BundledHistory.points(base: "SOL", quote: "USD", through: now).isEmpty)
    let inverse = try BundledHistory.points(base: "USD", quote: "BTC", through: now)
    #expect(btc.map(\.date) == inverse.map(\.date))
    #expect(zip(btc, inverse).allSatisfy { abs($0.value * $1.value - 1) < 0.00000001 })
  }

  @Test func sterlingParityUsesOnlyObservedMonthlyDates() throws {
    let now = try historyDate("2026-01-05T00:00:00Z")
    let gbp = try BundledHistory.points(base: "BTC", quote: "GBP", through: now)
    for code in ["GGP", "IMP", "JEP"] {
      #expect(try BundledHistory.points(base: "BTC", quote: code, through: now) == gbp)
    }
    #expect(
      try BundledHistory.points(base: "XAU", quote: "USD", through: now)
        .allSatisfy { $0.value.isFinite && $0.value > 0 })
  }
}

@Suite struct BundledAllHistoryTests {
  @Test func completedAllHistoryLoadsOfflineWithoutRequests() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DailyHistoryHTTP()
    await client.failRequests()
    let service = HistoryService(directory: directory, client: client)
    let now = try historyDate("2026-10-15T00:00:00Z")
    let result = await service.load(base: "BTC", quote: "USD", range: .all, now: now)
    #expect(result.issue == nil)
    let series = try #require(result.series)
    #expect(series.points.count > 150)
    let months = series.points.map { String($0.date.ISO8601Format().prefix(7)) }
    #expect(Set(months).count == months.count)
    #expect(
      series.points.filter { String($0.date.ISO8601Format().prefix(7)) == "2024-03" }.map(\.date)
        == [try historyDate("2024-03-02T00:00:00Z")])
    #expect(series.points.last?.date == (try historyDate("2026-09-01T00:00:00Z")))
    #expect(series.source.provider == .fawaz)
    #expect(series.source.contributingProviders == [.coinMetrics])
    #expect(await client.urls.isEmpty)
    let sol = await service.load(base: "SOL", quote: "USD", range: .all, now: now)
    #expect(sol.series?.points.first?.date == (try historyDate("2024-03-02T00:00:00Z")))
    #expect(sol.series?.source.contributingProviders == nil)
    #expect(await client.urls.isEmpty)
  }
}
