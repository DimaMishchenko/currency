import Foundation
import Testing

@testable import ExchangeRates

private actor IntervalHistoryHTTP: HTTPClient {
  private(set) var urls: [URL] = []
  private var shouldFail = false
  let data: Data

  init(data: Data) { self.data = data }

  func failRequests() { shouldFail = true }

  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    if shouldFail { throw RateError.http(503) }
    return data
  }
}

private func intervalDate(_ value: String) throws -> Date {
  try #require(ISO8601DateFormatter().date(from: value))
}

private func candleData(_ dates: [Date]) throws -> Data {
  try JSONEncoder()
    .encode(
      dates.enumerated()
        .map { index, date in
          [date.timeIntervalSince1970, 1, 100, 2, Double(index + 3), 1]
        })
}

@Suite struct HistoryIntervalTests {
  @Test func hourlyCandlesExcludeOlderAndUnfinishedBuckets() throws {
    let start = try intervalDate("2026-09-26T12:37:00Z")
    let end = start.addingTimeInterval(86400)
    let dates = try [
      "2026-09-26T12:00:00Z", "2026-09-26T13:00:00Z", "2026-09-27T11:00:00Z",
      "2026-09-27T12:00:00Z", "2026-09-27T13:00:00Z"
    ]
    .map(intervalDate)
    let points = try HistoryService.decodeCandles(
      candleData(dates), start: start, end: end, granularity: .hour)
    #expect(points.map(\.date) == [dates[1], dates[2]])
    #expect(points.map(\.value) == [4, 5])
    let atBoundary = try HistoryService.decodeCandles(
      candleData([dates[2]]), start: dates[2], end: dates[3], granularity: .hour)
    #expect(atBoundary.map(\.date) == [dates[2]])
  }

  @Test func hourlyWindowsKeepTheThreeHundredBucketLimit() {
    let start = Date(timeIntervalSince1970: 0)
    let end = start.addingTimeInterval(600 * 3600)
    let windows = HistoryService.candleWindows(start: start, end: end, granularity: .hour)
    #expect(windows.count == 3)
    #expect(windows.first?.start == start)
    #expect(windows.last?.end == end)
    #expect(windows[0].end == windows[1].start)
    #expect(windows[1].end == windows[2].start)
    #expect(windows.allSatisfy { $0.end.timeIntervalSince($0.start) <= 299 * 3600 })
  }

  @Test func dayUsesActualTwentyFourHourWindowAndHourlyProvenance() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try intervalDate("2026-09-27T12:37:00Z")
    let dates = try [
      "2026-09-26T12:00:00Z", "2026-09-26T13:00:00Z", "2026-09-27T11:00:00Z",
      "2026-09-27T12:00:00Z"
    ]
    .map(intervalDate)
    let client = IntervalHistoryHTTP(data: try candleData(dates))
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "USD", range: .day, now: now)
    #expect(result.issue == nil)
    #expect(result.series?.points.map(\.date) == [dates[1], dates[2]])
    #expect(
      result.series?.source == .init(provider: .coinbase, observation: .hourlyClose, timeZone: .gmt)
    )
    let url = try #require(await client.urls.first)
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.contains(URLQueryItem(name: "granularity", value: "3600")))
    #expect(query.contains(URLQueryItem(name: "start", value: "2026-09-26T12:37:00Z")))
    #expect(query.contains(URLQueryItem(name: "end", value: "2026-09-27T12:37:00Z")))
  }

  @Test(arguments: [("BTC", "EUR"), ("ETH", "GBP"), ("USDC", "EUR"), ("USDC", "GBP")])
  func nonDollarIntradayUsesDirectHourlyMarketAndItsOwnCache(
    base: String, quote: String
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try intervalDate("2026-09-27T12:37:00Z")
    let dates = try [
      "2026-09-26T12:00:00Z", "2026-09-26T13:00:00Z", "2026-09-27T11:00:00Z",
      "2026-09-27T12:00:00Z"
    ]
    .map(intervalDate)
    let client = IntervalHistoryHTTP(data: try candleData(dates))
    let service = HistoryService(directory: directory, client: client)
    let result = await service.load(base: base, quote: quote, range: .day, now: now)
    #expect(result.issue == nil)
    #expect(result.series?.points.map(\.date) == [dates[1], dates[2]])
    #expect(
      result.series?.source == .init(provider: .coinbase, observation: .hourlyClose, timeZone: .gmt)
    )
    let urls = await client.urls
    #expect(urls.count == 1)
    let url = try #require(urls.first)
    #expect(url.host == "api.exchange.coinbase.com")
    #expect(url.path == "/products/\(base)-\(quote)/candles")
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.contains(URLQueryItem(name: "granularity", value: "3600")))
    #expect(query.contains(URLQueryItem(name: "start", value: "2026-09-26T12:37:00Z")))
    #expect(query.contains(URLQueryItem(name: "end", value: "2026-09-27T12:37:00Z")))
    let file = directory.appendingPathComponent("history-\(base)-\(quote)-1.json")
    #expect(
      try JSONDecoder().decode(HistorySeries.self, from: Data(contentsOf: file)).points
        == result.series?.points)
    let fresh = await service.load(
      base: base, quote: quote, range: .day, now: now.addingTimeInterval(3599))
    #expect(await client.urls.count == 1)
    #expect(fresh.series?.fetchedAt == now)
    await client.failRequests()
    let expired = await service.load(
      base: base, quote: quote, range: .day, now: now.addingTimeInterval(3600))
    #expect(await client.urls.count == 2)
    #expect(expired.issue == .usingCachedSeries)
    #expect(expired.series?.points == result.series?.points)
  }

  @Test(arguments: [
    ("USD", "EUR"), ("BTC", "CZK"), ("AVAX", "GBP"), ("USDC", "USD"),
    ("BTC", "BTC")
  ])
  func unsupportedIntradayRoutesNeverRequestOrSave(base: String, quote: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = IntervalHistoryHTTP(data: Data())
    #expect(!HistoryService.supportsIntraday(base: base, quote: quote))
    let result = await HistoryService(directory: directory, client: client)
      .load(base: base, quote: quote, range: .day)
    #expect(result.series == nil)
    #expect(result.issue == (base == quote ? .unsupportedPair : .intradayUnavailable))
    #expect(await client.urls.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }

  @Test func directIntradayQuoteCachesRemainIndependent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try intervalDate("2026-09-27T12:00:00Z")
    let client = IntervalHistoryHTTP(
      data: try candleData([now.addingTimeInterval(-7200), now.addingTimeInterval(-3600)]))
    let service = HistoryService(directory: directory, client: client)
    for quote in ["EUR", "GBP", "EUR", "GBP"] {
      #expect(await service.load(base: "BTC", quote: quote, range: .day, now: now).issue == nil)
    }
    #expect(
      await client.urls.map(\.path) == ["/products/BTC-EUR/candles", "/products/BTC-GBP/candles"])
  }

  @Test func dayDefaultCacheExpiresAtOneHourAndPreservesOfflineHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try intervalDate("2026-09-27T12:00:00Z")
    let client = IntervalHistoryHTTP(
      data: try candleData([now.addingTimeInterval(-7200), now.addingTimeInterval(-3600)]))
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: "BTC", quote: "USD", range: .day, now: now)
    await client.failRequests()
    let fresh = await service.load(
      base: "BTC", quote: "USD", range: .day, now: now.addingTimeInterval(3599))
    #expect(await client.urls.count == 1)
    #expect(fresh.issue == nil)
    let expired = await service.load(
      base: "BTC", quote: "USD", range: .day, now: now.addingTimeInterval(3600))
    #expect(await client.urls.count == 2)
    #expect(expired.series?.points == first.series?.points)
    #expect(expired.series?.fetchedAt == first.series?.fetchedAt)
    #expect(expired.issue == .usingCachedSeries)
  }

  @Test func fiatIntradayIgnoresCacheAndNeverRequestsDailyRates() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = try intervalDate("2026-09-27T12:00:00Z")
    let saved = HistorySeries(
      points: [HistoryPoint(date: now, value: 0.9)],
      source: .init(provider: .frankfurter, observation: .dailyReference), fetchedAt: now)
    try JSONEncoder().encode(saved)
      .write(to: directory.appendingPathComponent("history-USD-EUR-1.json"))
    let client = IntervalHistoryHTTP(data: Data())
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "USD", quote: "EUR", range: .day, now: now)
    #expect(result.series == nil)
    #expect(result.issue == .intradayUnavailable)
    #expect(await client.urls.isEmpty)
  }

  @Test func cryptoYearToDateStartsAtJanuaryFirstAndIncludesLeapDay() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try intervalDate("2024-03-02T12:30:00Z")
    let dates = try [
      "2023-12-31T00:00:00Z", "2024-01-01T00:00:00Z", "2024-02-29T00:00:00Z",
      "2024-03-01T00:00:00Z", "2024-03-02T00:00:00Z"
    ]
    .map(intervalDate)
    let client = IntervalHistoryHTTP(data: try candleData(dates))
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "USD", range: .yearToDate, now: now)
    #expect(result.issue == nil)
    #expect(result.series?.points.map(\.date) == Array(dates[1...3]))
    #expect(result.series?.source.observation == .dailyClose)
    let url = try #require(await client.urls.first)
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.contains(URLQueryItem(name: "start", value: "2024-01-01T00:00:00Z")))
    #expect(query.contains(URLQueryItem(name: "end", value: "2024-03-02T00:00:00Z")))
    #expect(query.contains(URLQueryItem(name: "granularity", value: "86400")))
  }

  @Test func cryptoYearToDateOnJanuaryFirstHasNoCompletedDays() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = IntervalHistoryHTTP(data: Data())
    let now = try intervalDate("2026-01-01T23:59:00Z")
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "USD", range: .yearToDate, now: now)
    #expect(result.series == nil)
    #expect(result.issue == .unavailable)
    #expect(await client.urls.isEmpty)
  }

  @Test func fiatYearToDateRequestsJanuaryFirstAndFiltersPreviousYear() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try intervalDate("2024-03-01T12:00:00Z")
    let client = IntervalHistoryHTTP(
      data: Data(
        #"[{"date":"2023-12-31","base":"EUR","quote":"USD","rate":1.0},{"date":"2024-01-01","base":"EUR","quote":"USD","rate":1.1},{"date":"2024-02-29","base":"EUR","quote":"USD","rate":1.2},{"date":"2024-03-02","base":"EUR","quote":"USD","rate":1.3}]"#
          .utf8))
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "EUR", quote: "USD", range: .yearToDate, now: now)
    #expect(result.issue == nil)
    #expect(result.series?.points.map(\.value) == [1.1, 1.2])
    #expect(result.series?.source.observation == .dailyReference)
    let url = try #require(await client.urls.first)
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.contains(URLQueryItem(name: "from", value: "2024-01-01")))
    #expect(query.contains(URLQueryItem(name: "to", value: "2024-03-01")))
    #expect(!query.contains(where: { $0.name == "group" }))
  }

  @Test func yearToDateRolloverNeverUsesPreviousYearCacheEvenOnFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try intervalDate("2025-12-31T23:59:00Z")
    let client = IntervalHistoryHTTP(
      data: Data(
        #"[{"date":"2025-01-01","base":"EUR","quote":"USD","rate":1.1},{"date":"2025-12-31","base":"EUR","quote":"USD","rate":1.2}]"#
          .utf8))
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: "EUR", quote: "USD", range: .yearToDate, now: now)
    #expect(first.series?.points.count == 2)
    await client.failRequests()
    let rollover = await service.load(
      base: "EUR", quote: "USD", range: .yearToDate, now: now.addingTimeInterval(120))
    #expect(await client.urls.count == 2)
    #expect(rollover.series == nil)
    #expect(rollover.issue == .unavailable)
    let saved = directory.appendingPathComponent("history-EUR-USD--1-2025.json")
    #expect(
      try JSONDecoder().decode(HistorySeries.self, from: Data(contentsOf: saved)).points
        == first.series?.points)
  }

  @Test func yearToDateRefreshCanFallBackWithinTheSameYear() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try intervalDate("2026-09-27T12:00:00Z")
    let client = IntervalHistoryHTTP(
      data: Data(
        #"[{"date":"2026-01-01","base":"EUR","quote":"USD","rate":1.1},{"date":"2026-09-27","base":"EUR","quote":"USD","rate":1.2}]"#
          .utf8))
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: "EUR", quote: "USD", range: .yearToDate, now: now)
    await client.failRequests()
    let expired = await service.load(
      base: "EUR", quote: "USD", range: .yearToDate, now: now.addingTimeInterval(21600))
    #expect(await client.urls.count == 2)
    #expect(expired.series?.points == first.series?.points)
    #expect(expired.series?.fetchedAt == first.series?.fetchedAt)
    #expect(expired.issue == .usingCachedSeries)
  }
}
