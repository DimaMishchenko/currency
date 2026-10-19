import Foundation
import Testing

@testable import ExchangeRates

private actor WeeklyHistoryHTTP: HTTPClient {
  private(set) var urls: [URL] = []
  var hours: Int
  var failing = false
  var delay: Duration?

  init(hours: Int = 168, delay: Duration? = nil) { self.hours = hours; self.delay = delay }
  func fail() { failing = true }

  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    if let delay { try await Task.sleep(for: delay) }
    if failing { throw RateError.unavailable }
    if url.host == "community-api.coinmetrics.io" {
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
      func value(_ key: String) throws -> String {
        try #require(query.first { $0.name == key }?.value)
      }
      #expect(try value("frequency") == "1h")
      let end = try historyDate(value("end_time"))
      let assets = try value("assets").split(separator: ",")
      let rows = (0..<hours)
        .flatMap { offset in
          assets.map { asset in
            [
              "asset": String(asset),
              "time": end.addingTimeInterval(Double(offset - hours) * 3600).ISO8601Format(),
              "ReferenceRateUSD": asset == "eth" ? "20" : "100"
            ]
          }
        }
      return try JSONSerialization.data(withJSONObject: ["data": rows])
    }
    let day: String
    if url.host == "cdn.jsdelivr.net" {
      day = String(url.path.split(separator: "@").last!.prefix(10))
    } else {
      day = String(url.host!.prefix(10))
    }
    let dayNumber = Int(day.suffix(2))!
    var rates = Dictionary(
      uniqueKeysWithValues: CurrencyCatalog.crypto.map { ($0.lowercased(), 0.02) })
    rates.merge(["usd": 2, "gbp": Double(dayNumber), "xau": 0.001]) { _, new in new }
    return try JSONSerialization.data(withJSONObject: ["date": day, "eur": rates])
  }
}

@Suite struct WeeklyHistoryTests {
  let now = Date(timeIntervalSince1970: 1_792_065_600)

  func directory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  @Test(arguments: Array(CurrencyCatalog.crypto))
  func everyCatalogCryptoRequestsHourlyWeek(code: String) async throws {
    let directory = directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = WeeklyHistoryHTTP()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: code, quote: "USD", range: .week, now: now)
    #expect(result.issue == nil)
    #expect(result.series?.points.count == 168)
    #expect(result.series?.source.observation == .hourlyReference)
    let urls = await client.urls
    #expect(urls.count == 1)
    #expect(
      URLComponents(url: urls[0], resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "assets" }?
        .value == code.lowercased())
  }

  @Test(arguments: [("USD", "BTC", 0.01), ("BTC", "ETH", 5.0), ("ETH", "BTC", 0.2)])
  func inverseAndCryptoCrossRates(base: String, quote: String, expected: Double) async throws {
    let directory = directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = await HistoryService(directory: directory, client: WeeklyHistoryHTTP())
      .load(base: base, quote: quote, range: .week, now: now)
    #expect(result.series?.points.count == 168)
    #expect(result.series?.points.allSatisfy { abs($0.value - expected) < 0.000001 } == true)
  }

  @Test(arguments: ["GBP", "GGP", "IMP", "JEP", "XAU"])
  func nonCryptoLegUsesEachUtcDaysReference(code: String) async throws {
    let directory = directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = WeeklyHistoryHTTP()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: code, range: .week, now: now)
    let series = try #require(result.series)
    #expect(series.source.observation == .hourlyReference)
    #expect(series.source.contributingProviders == [.fawaz])
    for point in series.points {
      let dayNumber = Double(String(point.date.ISO8601Format().prefix(10)).suffix(2))!
      let expected = code == "XAU" ? 0.05 : 50 * dayNumber
      #expect(abs(point.value - expected) < 0.000001)
    }
    let days = Set(series.points.map { String($0.date.ISO8601Format().prefix(10)) })
    #expect(await client.urls.count == days.count + 1)
  }

  @Test func incompleteWeekFallsBackAndRetriesHourlyAfterAnHour() async throws {
    let directory = directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = WeeklyHistoryHTTP(hours: 24)
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: "BTC", quote: "USD", range: .week, now: now)
    #expect(first.issue == nil)
    #expect(first.series?.source.observation == .dailyReference)
    #expect(first.series?.points.count == 8)
    let firstCount = await client.urls.count
    let reused = await service.load(
      base: "BTC", quote: "USD", range: .week, now: now.addingTimeInterval(3599),
      cacheLifetime: 86400)
    #expect(reused.series?.points == first.series?.points)
    #expect(await client.urls.count == firstCount)
    _ = await service.load(
      base: "BTC", quote: "USD", range: .week, now: now.addingTimeInterval(3600),
      cacheLifetime: 86400)
    #expect(await client.urls.count == firstCount + 1)
  }

  @Test func dailyRefreshDuringHourlyCooldownDoesNotPostponeRetry() async throws {
    let directory = directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = WeeklyHistoryHTTP(hours: 24)
    let service = HistoryService(directory: directory, client: client)
    let file = directory.appendingPathComponent("history-v3-BTC-USD-7.json")
    _ = await service.load(
      base: "BTC", quote: "USD", range: .week, now: now, cacheLifetime: 86400)
    let attemptedAt = now.addingTimeInterval(5.5 * 3600)
    _ = await service.load(
      base: "BTC", quote: "USD", range: .week, now: attemptedAt, cacheLifetime: 86400)
    let dailyRefreshAt = now.addingTimeInterval(6 * 3600 + 60)
    let refreshed = await service.load(
      base: "BTC", quote: "USD", range: .week, now: dailyRefreshAt)
    #expect(refreshed.issue == nil)
    let record = try JSONDecoder().decode(HistoryCacheRecord.self, from: Data(contentsOf: file))
    #expect(record.series.fetchedAt == dailyRefreshAt)
    #expect(record.weeklyHourlyAttemptedAt == attemptedAt)
    #expect(await client.urls.filter { $0.host == "community-api.coinmetrics.io" }.count == 2)
    _ = await service.load(
      base: "BTC", quote: "USD", range: .week,
      now: attemptedAt.addingTimeInterval(3599), cacheLifetime: 1)
    #expect(await client.urls.filter { $0.host == "community-api.coinmetrics.io" }.count == 2)
    _ = await service.load(
      base: "BTC", quote: "USD", range: .week,
      now: attemptedAt.addingTimeInterval(3600), cacheLifetime: 1)
    #expect(await client.urls.filter { $0.host == "community-api.coinmetrics.io" }.count == 3)
    let retried = try JSONDecoder().decode(HistoryCacheRecord.self, from: Data(contentsOf: file))
    #expect(retried.weeklyHourlyAttemptedAt == attemptedAt.addingTimeInterval(3600))
  }

  @Test func hourlyCacheExpiresAtUtcBoundaryDespiteWidgetLifetime() async throws {
    let directory = directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = WeeklyHistoryHTTP()
    let service = HistoryService(directory: directory, client: client)
    let fetched = now.addingTimeInterval(3300)
    let first = await service.load(
      base: "BTC", quote: "USD", range: .week, now: fetched, cacheLifetime: 86400)
    await client.fail()
    let fresh = await service.load(
      base: "BTC", quote: "USD", range: .week, now: fetched.addingTimeInterval(299),
      cacheLifetime: 86400)
    #expect(fresh.issue == nil)
    #expect(await client.urls.count == 1)
    let stale = await service.load(
      base: "BTC", quote: "USD", range: .week, now: fetched.addingTimeInterval(300),
      cacheLifetime: 86400)
    #expect(stale.issue == .usingCachedSeries)
    #expect(stale.series?.points == first.series?.points)
  }

  @Test func oldDailyCacheUpgradesAndFailedUpgradeDoesNotStorm() async throws {
    for fail in [false, true] {
      let directory = directory()
      defer { try? FileManager.default.removeItem(at: directory) }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("history-v3-BTC-USD-7.json")
      let old = HistorySeries(
        points: (0...7)
          .map { .init(date: now.addingTimeInterval(Double($0 - 7) * 86400), value: 100) },
        source: .init(provider: .fawaz, observation: .dailyReference), fetchedAt: now)
      try JSONEncoder().encode(old).write(to: file)
      let client = WeeklyHistoryHTTP()
      if fail { await client.fail() }
      let first = await HistoryService(directory: directory, client: client)
        .load(base: "BTC", quote: "USD", range: .week, now: now)
      #expect(first.series?.source.observation == (fail ? .dailyReference : .hourlyReference))
      #expect(first.issue == (fail ? .usingCachedSeries : nil))
      let calls = await client.urls.count
      let second = await HistoryService(directory: directory, client: client)
        .load(base: "BTC", quote: "USD", range: .week, now: now.addingTimeInterval(60))
      #expect(second.issue == nil)
      #expect(await client.urls.count == calls)
    }
  }

  @Test func cancellationPreservesDailyCacheWithoutStampingAttempt() async throws {
    let directory = directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let old = HistorySeries(
      points: [
        .init(date: now.addingTimeInterval(-86400), value: 100), .init(date: now, value: 100)
      ],
      source: .init(provider: .fawaz, observation: .dailyReference), fetchedAt: now)
    let file = directory.appendingPathComponent("history-v3-BTC-USD-7.json")
    let data = try JSONEncoder().encode(old)
    try data.write(to: file)
    let client = WeeklyHistoryHTTP(delay: .seconds(10))
    let service = HistoryService(directory: directory, client: client)
    let task = Task { await service.load(base: "BTC", quote: "USD", range: .week, now: now) }
    for _ in 0..<300 {
      if await !client.urls.isEmpty { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    task.cancel()
    let result = await task.value
    #expect(result.issue == .usingCachedSeries)
    #expect(result.series?.points == old.points)
    #expect(await client.urls.count == 1)
    #expect(try Data(contentsOf: file) == data)
  }

  @Test func identicalConcurrentWeeksShareProviderWork() async throws {
    let directory = directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = WeeklyHistoryHTTP(delay: .milliseconds(100))
    let service = HistoryService(directory: directory, client: client)
    async let first = service.load(base: "BTC", quote: "USD", range: .week, now: now)
    async let second = service.load(base: "BTC", quote: "USD", range: .week, now: now)
    let results = await [first, second]
    #expect(results.allSatisfy { $0.series?.source.observation == .hourlyReference })
    #expect(await client.urls.count == 1)
  }

  @Test func cancellingOneConsumerPreservesAnotherConsumersSharedLoad() async throws {
    let directory = directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = WeeklyHistoryHTTP(delay: .milliseconds(200))
    let service = HistoryService(directory: directory, client: client)
    let first = Task { await service.load(base: "BTC", quote: "USD", range: .week, now: now) }
    for _ in 0..<300 {
      if await !client.urls.isEmpty { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let second = Task { await service.load(base: "BTC", quote: "USD", range: .week, now: now) }
    try await Task.sleep(for: .milliseconds(20))
    first.cancel()
    let result = await second.value
    _ = await first.value
    #expect(result.issue == nil)
    #expect(result.series?.source.observation == .hourlyReference)
    #expect(await client.urls.count == 1)
  }

  @Test func monthCryptoAndFiatWeekDoNotRequestHourlyHistory() async throws {
    let directory = directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DailyHistoryHTTP()
    let service = HistoryService(directory: directory, client: client)
    let crypto = await service.load(base: "BTC", quote: "USD", range: .month, now: now)
    let fiat = await service.load(base: "EUR", quote: "USD", range: .week, now: now)
    #expect(crypto.series?.source.observation == .dailyReference)
    #expect(fiat.series?.source.observation == .dailyReference)
    #expect(await client.urls.allSatisfy { $0.host != "community-api.coinmetrics.io" })
  }

  @Test func coverageRejectsShortWindowsAndLargeInteriorGaps() {
    let points = (0..<168)
      .map {
        HistoryPoint(date: now.addingTimeInterval(Double($0 - 168) * 3600), value: 100)
      }
    #expect(HistoryService.coversWeek(points, ending: now))
    #expect(!HistoryService.coversWeek(Array(points.suffix(24)), ending: now))
    #expect(!HistoryService.coversWeek(Array(points.dropLast(4)), ending: now))
    #expect(!HistoryService.coversWeek(Array(points.dropFirst(3)), ending: now))
    #expect(
      !HistoryService.coversWeek(
        points.enumerated().filter { !(80...84).contains($0.offset) }
          .map(\.element), ending: now))
  }
}
