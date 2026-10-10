import Foundation
import Testing

@testable import ExchangeRates

actor DailyHistoryHTTP: HTTPClient {
  private(set) var urls: [URL] = []
  var failing = false
  var wrongDate = false
  var failPrimary = false
  var missingDay: String?
  func failRequests() { failing = true }
  func returnWrongDate() { wrongDate = true }
  func setMissingDay(_ day: String) { missingDay = day }
  func failPrimaryRequests() { failPrimary = true }

  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    if failing || (failPrimary && url.host == "cdn.jsdelivr.net") { throw RateError.http(503) }
    let day: String
    if let segment = url.absoluteString.components(separatedBy: "currency-api@").last,
      segment != url.absoluteString
    {
      day = String(segment.prefix(10))
    } else {
      day = String((url.host ?? "").prefix(10))
    }
    if day == missingDay { throw RateError.http(404) }
    let date = wrongDate ? "2020-01-01" : day
    return Data(
      "{\"date\":\"\(date)\",\"eur\":{\"usd\":2,\"btc\":0.00002,\"eth\":0.0005,\"xau\":0.001,\"xag\":0.05}}"
        .utf8)
  }
}

func historyDate(_ string: String) throws -> Date {
  try #require(ISO8601DateFormatter().date(from: string))
}

@Suite struct HistoryTests {
  @Test(arguments: [
    ("BTC", "USD", 100_000.0), ("BTC", "ETH", 25.0),
    ("USD", "BTC", 0.00001), ("XAU", "EUR", 1_000.0), ("XAU", "XAG", 50.0)
  ])
  func dailyHistoryCrossRatesUseOnlyFawaz(base: String, quote: String, value: Double) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DailyHistoryHTTP()
    let now = try historyDate("2026-01-08T12:00:00Z")
    let result = await HistoryService(directory: directory, client: client)
      .load(base: base, quote: quote, range: .week, now: now)
    let series = try #require(result.series)
    #expect(result.issue == nil)
    #expect(series.points.count == 8)
    #expect(series.points.allSatisfy { abs($0.value - value) < 0.000001 })
    #expect(series.source == .init(provider: .fawaz, observation: .dailyReference, timeZone: .gmt))
    #expect(await client.urls.allSatisfy { $0.host == "cdn.jsdelivr.net" })
  }

  @Test func sharedDatedPayloadsAvoidRepeatedPairAndRangeRequests() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DailyHistoryHTTP()
    let now = try historyDate("2026-01-08T12:00:00Z")
    let service = HistoryService(directory: directory, client: client, policy: .coinbaseEnhanced)
    let first = await service.load(base: "BTC", quote: "EUR", range: .week, now: now)
    #expect(first.series?.source.latestObservation == nil)
    _ = await service.load(base: "USD", quote: "XAU", range: .week, now: now)
    _ = await service.load(
      base: "BTC", quote: "EUR", range: .week, now: now.addingTimeInterval(21600))
    #expect(await client.urls.count == 8)
    #expect(await client.urls.allSatisfy { $0.host == "cdn.jsdelivr.net" })
  }

  @Test func allHistorySamplesAvailableMonthEndsWithoutDailyFanout() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DailyHistoryHTTP()
    let now = try historyDate("2026-10-09T12:00:00Z")
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "EUR", quote: "USD", range: .all, now: now)
    #expect(result.series?.source.observation == .monthlyReference)
    #expect(result.series?.points.count == 32)
    #expect(result.series?.points.first?.date == (try historyDate("2024-03-31T00:00:00Z")))
    #expect(result.series?.points.last?.date == (try historyDate("2026-10-09T00:00:00Z")))
    #expect(await client.urls.count == 32)
  }

  @Test func yearToDateUsesJanuaryFirstAndArchiveBoundary() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DailyHistoryHTTP()
    let service = HistoryService(directory: directory, client: client)
    let result = await service.load(
      base: "EUR", quote: "USD", range: .yearToDate,
      now: try historyDate("2026-01-03T12:00:00Z"))
    #expect(result.series?.points.count == 3)
    #expect(result.series?.points.first?.date == (try historyDate("2026-01-01T00:00:00Z")))
    let archive = HistoryService.dailyDates(
      start: .distantPast,
      now: try historyDate("2024-03-03T12:00:00Z"), monthly: false)
    #expect(archive.count == 2)
    #expect(archive.first == (try historyDate("2024-03-02T00:00:00Z")))
    await client.failRequests()
    let rollover = await service.load(
      base: "EUR", quote: "USD", range: .yearToDate,
      now: try historyDate("2027-01-01T12:00:00Z"))
    #expect(rollover.series == nil)
  }

  @Test func datedEndpointFallbackAndWrongDateRejection() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DailyHistoryHTTP()
    await client.failPrimaryRequests()
    let now = try historyDate("2026-01-03T12:00:00Z")
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "EUR", quote: "USD", range: .yearToDate, now: now)
    #expect(result.series?.points.count == 3)
    #expect(await client.urls.count == 6)
    await client.returnWrongDate()
    let invalid = await HistoryService(
      directory: directory.appendingPathComponent("invalid"), client: client
    )
    .load(base: "EUR", quote: "USD", range: .yearToDate, now: now)
    #expect(invalid.series == nil)
    #expect(invalid.issue == .unavailable)
  }

  @Test func unavailableArchiveDatesAreSkippedWithoutInventingObservations() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DailyHistoryHTTP()
    await client.setMissingDay("2026-01-02")
    let result = await HistoryService(directory: directory, client: client)
      .load(
        base: "EUR", quote: "USD", range: .yearToDate,
        now: try historyDate("2026-01-03T12:00:00Z"))
    #expect(result.issue == nil)
    #expect(
      result.series?.points.map { String($0.date.ISO8601Format().prefix(10)) }
        == ["2026-01-01", "2026-01-03"])
    #expect(await client.urls.count == 4)
  }

  @Test func historySortsAndUsesCompletedClose() throws {
    let rows = Data("[[172800,1,9,3,5,20],[86400,1,9,3,4,20],[259200,1,9,3,8,20]]".utf8)
    let points = try HistoryService.decodeCandles(
      rows, start: Date(timeIntervalSince1970: 86400), end: Date(timeIntervalSince1970: 300000))
    #expect(points.map(\.value) == [4, 5])
    #expect(throws: (any Error).self) {
      try HistoryService.decodeCandles(Data("[[1,2]]".utf8), start: .distantPast, end: .now)
    }
  }
}
