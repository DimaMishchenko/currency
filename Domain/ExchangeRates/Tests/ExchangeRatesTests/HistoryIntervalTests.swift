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

private actor EndpointHistoryHTTP: HTTPClient {
  private(set) var urls: [URL] = []
  private var failing = false
  private let delay: Duration

  init(delay: Duration = .zero) { self.delay = delay }
  func failRequests() { failing = true }
  func resumeRequests() { failing = false }

  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    if failing { throw RateError.http(503) }
    try await Task.sleep(for: delay)
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    guard query?.contains(URLQueryItem(name: "granularity", value: "3600")) == true,
      let end = query?.first(where: { $0.name == "end" })?.value,
      let date = ISO8601DateFormatter().date(from: end)
    else { throw RateError.invalidData }
    let completed = floor(date.timeIntervalSince1970 / 3600) * 3600
    let value: Double =
      switch url.path {
      case "/products/ETH-USD/candles": 2_000
      case "/products/USDC-EUR/candles": 0.9
      default: 84_608.1
      }
    return try JSONEncoder()
      .encode([
        [completed - 7200, 1, 100_000, 2, value - 0.1, 1],
        [completed - 3600, 1, 100_000, 2, value, 1],
        [completed, 1, 100_000, 2, 99_999, 1]
      ])
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
  @Test func hourlyCachedEndpointIsSharedAcrossLongRanges() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = try intervalDate("2026-09-30T12:37:00Z")
    let latest = HistoryPoint(date: try intervalDate("2026-09-30T11:00:00Z"), value: 84_608.1)
    let hourly = HistorySeries(
      points: [HistoryPoint(date: now.addingTimeInterval(-7200), value: 84_000), latest],
      source: .init(provider: .coinbase, observation: .hourlyClose, timeZone: .gmt), fetchedAt: now)
    try JSONEncoder().encode(hourly)
      .write(to: directory.appendingPathComponent("history-BTC-USD-1.json"))
    let client = IntervalHistoryHTTP(data: Data())
    let service = HistoryService(directory: directory, client: client)
    for range in HistoryRange.allCases where range != .day {
      let daily = HistorySeries(
        points: [
          HistoryPoint(date: try intervalDate("2026-09-01T00:00:00Z"), value: 80_000),
          HistoryPoint(date: try intervalDate("2026-09-29T00:00:00Z"), value: 83_638.4)
        ],
        source: .init(
          provider: .coinbase,
          observation: range == .all ? .monthlyLastClose : .dailyClose, timeZone: .gmt),
        fetchedAt: now)
      let interval = range == .yearToDate ? "-1-2026" : String(range.rawValue)
      let file = directory.appendingPathComponent("history-BTC-USD-\(interval).json")
      let saved = try JSONEncoder().encode(daily)
      try saved.write(to: file)
      let result = await service.load(base: "BTC", quote: "USD", range: range, now: now)
      #expect(result.issue == nil)
      #expect(result.series?.points == daily.points + [latest])
      #expect(result.series?.source.observation == daily.source.observation)
      #expect(result.series?.source.latestObservation == .hourlyClose)
      #expect(try Data(contentsOf: file) == saved)
    }
    #expect(await client.urls.isEmpty)
  }

  @Test(arguments: [
    ("BTC", "USD"), ("BTC", "EUR"), ("ETH", "GBP"), ("BTC", "ETH"), ("USDC", "BTC")
  ])
  func longRangesRefreshOnlyTheirCanonicalHourlyEndpoint(base: String, quote: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = try intervalDate("2026-09-30T12:37:00Z")
    let daily = HistorySeries(
      points: [
        HistoryPoint(date: try intervalDate("2026-09-28T00:00:00Z"), value: 80_000),
        HistoryPoint(date: try intervalDate("2026-09-29T00:00:00Z"), value: 83_638.4)
      ], source: .init(provider: .coinbase, observation: .dailyClose, timeZone: .gmt),
      fetchedAt: now)
    let saved = try JSONEncoder().encode(daily)
    let client = EndpointHistoryHTTP()
    let service = HistoryService(directory: directory, client: client)
    let ranges = HistoryRange.allCases.filter { $0 != .day }
    for range in ranges {
      let interval = range == .yearToDate ? "-1-2026" : String(range.rawValue)
      try saved.write(
        to: directory.appendingPathComponent("history-\(base)-\(quote)-\(interval).json"))
      let result = await service.load(
        base: base, quote: quote, range: range, now: now, cacheLifetime: 86_400)
      #expect(result.issue == nil)
      #expect(result.series?.points.last?.date == (try intervalDate("2026-09-30T11:00:00Z")))
      #expect(result.series?.source.observation == .dailyClose)
      #expect(result.series?.source.latestObservation == .hourlyClose)
      #expect(result.series?.fetchedAt == now)
    }
    let day = await service.load(base: base, quote: quote, range: .day, now: now)
    let expected = try #require(day.series?.points.last)
    let legs = CurrencyCatalog.crypto.contains(quote) ? 2 : 1
    #expect(await client.urls.count == legs)
    for range in ranges {
      let interval = range == .yearToDate ? "-1-2026" : String(range.rawValue)
      let file = directory.appendingPathComponent("history-\(base)-\(quote)-\(interval).json")
      let result = await service.load(
        base: base, quote: quote, range: range, now: now, cacheLifetime: 86_400)
      #expect(result.series?.points == daily.points + [expected])
      #expect(try Data(contentsOf: file) == saved)
    }
    let nextHour = try intervalDate("2026-09-30T13:00:00Z")
    let refreshed = await service.load(
      base: base, quote: quote, range: .year, now: nextHour, cacheLifetime: 86_400)
    #expect(refreshed.series?.points.last?.date == (try intervalDate("2026-09-30T12:00:00Z")))
    #expect(refreshed.series?.fetchedAt == nextHour)
    #expect(await client.urls.count == 2 * legs)
    #expect(
      try Data(contentsOf: directory.appendingPathComponent("history-\(base)-\(quote)-365.json"))
        == saved)
    let urls = await client.urls
    #expect(urls.allSatisfy { $0.host == "api.exchange.coinbase.com" })
    if !CurrencyCatalog.crypto.contains(quote) {
      #expect(urls.allSatisfy { $0.path == "/products/\(base)-\(quote)/candles" })
    }
  }

  @Test(arguments: [true, false])
  func hourlyUnavailableRetainsTruthfulDailyOrSavedEndpoint(hasHourlyCache: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = try intervalDate("2026-09-30T12:37:00Z")
    let daily = HistorySeries(
      points: [
        HistoryPoint(date: now.addingTimeInterval(-3 * 86400), value: 80_000),
        HistoryPoint(date: try intervalDate("2026-09-29T00:00:00Z"), value: 83_638.4)
      ], source: .init(provider: .coinbase, observation: .dailyClose, timeZone: .gmt),
      fetchedAt: now)
    try JSONEncoder().encode(daily)
      .write(to: directory.appendingPathComponent("history-BTC-USD-30.json"))
    let latest = HistoryPoint(date: try intervalDate("2026-09-30T10:00:00Z"), value: 84_000)
    let hourly = HistorySeries(
      points: [HistoryPoint(date: latest.date.addingTimeInterval(-3600), value: 83_000), latest],
      source: .init(provider: .coinbase, observation: .hourlyClose, timeZone: .gmt),
      fetchedAt: try intervalDate("2026-09-30T11:37:00Z"))
    if hasHourlyCache {
      try JSONEncoder().encode(hourly)
        .write(to: directory.appendingPathComponent("history-BTC-USD-1.json"))
    }
    let client = EndpointHistoryHTTP()
    await client.failRequests()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "USD", range: .month, now: now)
    #expect(result.series?.points == daily.points + (hasHourlyCache ? [latest] : []))
    #expect(result.issue == (hasHourlyCache ? .usingCachedSeries : nil))
    #expect(result.series?.source.latestObservation == (hasHourlyCache ? .hourlyClose : nil))
    #expect(result.series?.fetchedAt == (hasHourlyCache ? hourly.fetchedAt : daily.fetchedAt))
    #expect(await client.urls.count == 1)
  }

  @Test(arguments: [false, true])
  func midnightPrefersEqualHourlyCloseButRejectsOlderSavedClose(
    hourlyUnavailable: Bool
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = try intervalDate("2026-09-30T00:05:00Z")
    let daily = HistorySeries(
      points: [
        HistoryPoint(date: try intervalDate("2026-09-28T00:00:00Z"), value: 80_000),
        HistoryPoint(date: try intervalDate("2026-09-29T00:00:00Z"), value: 83_638.4)
      ], source: .init(provider: .coinbase, observation: .dailyClose, timeZone: .gmt),
      fetchedAt: now)
    let saved = try JSONEncoder().encode(daily)
    let file = directory.appendingPathComponent("history-BTC-USD-7.json")
    try saved.write(to: file)
    let hourly = HistorySeries(
      points: [
        HistoryPoint(date: try intervalDate("2026-09-29T21:00:00Z"), value: 81_000),
        HistoryPoint(date: try intervalDate("2026-09-29T22:00:00Z"), value: 82_000)
      ], source: .init(provider: .coinbase, observation: .hourlyClose, timeZone: .gmt),
      fetchedAt: try intervalDate("2026-09-29T23:45:00Z"))
    try JSONEncoder().encode(hourly)
      .write(to: directory.appendingPathComponent("history-BTC-USD-1.json"))
    let client = EndpointHistoryHTTP()
    if hourlyUnavailable { await client.failRequests() }
    let service = HistoryService(directory: directory, client: client)
    let atMidnight = await service.load(base: "BTC", quote: "USD", range: .week, now: now)
    let equalClose = HistoryPoint(date: try intervalDate("2026-09-29T23:00:00Z"), value: 84_608.1)
    #expect(atMidnight.series?.points == daily.points + (hourlyUnavailable ? [] : [equalClose]))
    #expect(atMidnight.series?.source.latestObservation == (hourlyUnavailable ? nil : .hourlyClose))
    #expect(await client.urls.count == 1)
    if !hourlyUnavailable {
      let day = await service.load(base: "BTC", quote: "USD", range: .day, now: now)
      #expect(atMidnight.series?.points.last == day.series?.points.last)
    }
    await client.resumeRequests()
    let afterHour = await service.load(
      base: "BTC", quote: "USD", range: .week, now: try intervalDate("2026-09-30T01:00:00Z"))
    #expect(afterHour.series?.points.last?.date == (try intervalDate("2026-09-30T00:00:00Z")))
    #expect(afterHour.series?.source.latestObservation == .hourlyClose)
    #expect(await client.urls.count == 2)
    #expect(try Data(contentsOf: file) == saved)
  }

  @Test func cancellingHourlyRefreshPreservesTheLongRangeCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = try intervalDate("2026-09-30T12:37:00Z")
    let daily = HistorySeries(
      points: [
        HistoryPoint(date: now.addingTimeInterval(-3 * 86400), value: 80_000),
        HistoryPoint(date: try intervalDate("2026-09-29T00:00:00Z"), value: 83_638.4)
      ], source: .init(provider: .coinbase, observation: .dailyClose, timeZone: .gmt),
      fetchedAt: now)
    let saved = try JSONEncoder().encode(daily)
    let file = directory.appendingPathComponent("history-BTC-USD-365.json")
    try saved.write(to: file)
    let client = EndpointHistoryHTTP(delay: .seconds(10))
    let service = HistoryService(directory: directory, client: client)
    let task = Task { await service.load(base: "BTC", quote: "USD", range: .year, now: now) }
    for _ in 0..<300 {
      if await !client.urls.isEmpty { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await client.urls.count == 1)
    task.cancel()
    let result = await task.value
    #expect(result.series?.points == daily.points)
    #expect(try Data(contentsOf: file) == saved)
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("history-BTC-USD-1.json").path))
  }

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
    let expiry = HistoryService.nextHour(after: now)
    let fresh = await service.load(
      base: base, quote: quote, range: .day, now: expiry.addingTimeInterval(-1))
    #expect(await client.urls.count == 1)
    #expect(fresh.series?.fetchedAt == now)
    await client.failRequests()
    let expired = await service.load(
      base: base, quote: quote, range: .day, now: expiry)
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
