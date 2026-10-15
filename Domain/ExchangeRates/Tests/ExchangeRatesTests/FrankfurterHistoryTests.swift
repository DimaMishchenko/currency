import Foundation
import Testing

@testable import ExchangeRates

private actor FiatHistoryHTTP: HTTPClient {
  private(set) var urls: [URL] = []
  let response: String?
  let ecbResponse: String?
  let cbuResponse: String?
  var failing = false
  func fail() { failing = true }
  let fallback = DailyHistoryHTTP()

  init(response: String? = nil, ecbResponse: String? = nil, cbuResponse: String? = nil) {
    self.response = response
    self.ecbResponse = ecbResponse
    self.cbuResponse = cbuResponse
  }

  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    if failing { throw RateError.http(503) }
    guard url.host == "api.frankfurter.dev" else { return try await fallback.get(url) }
    if response == "unsupported" { throw RateError.http(404) }
    if let response { return Data(response.utf8) }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    func value(_ name: String) -> String { query.first { $0.name == name }!.value! }
    if value("providers") == "ECB", let ecbResponse { return Data(ecbResponse.utf8) }
    if value("providers") == "CBU", let cbuResponse { return Data(cbuResponse.utf8) }
    let first = try historyDate(value("from") + "T00:00:00Z")
    let last = try historyDate(value("to") + "T00:00:00Z")
    let count = Int(last.timeIntervalSince(first) / 86400)
    let rates = ["USD": 2.0, "GBP": 1.0, "CZK": 50.0, "AED": 4.0]
    let rows: [[String: Any]] = (0...count)
      .flatMap { offset in
        value("quotes").split(separator: ",")
          .map { code in
            [
              "date": String(
                first.addingTimeInterval(Double(offset) * 86400).ISO8601Format().prefix(10)),
              "base": "EUR", "quote": String(code), "rate": rates[String(code), default: 2]
            ]
          }
      }
    return try JSONSerialization.data(withJSONObject: rows)
  }
}

@Suite struct FrankfurterHistoryTests {
  @Test(arguments: [("EUR", "USD"), ("CZK", "GBP"), ("USD", "EUR")])
  func yearUsesOneScopedRequestAndFreshCache(base: String, quote: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = try historyDate("2026-10-15T12:00:00Z")
    let client = FiatHistoryHTTP()
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: base, quote: quote, range: .year, now: now)
    #expect(first.issue == nil)
    #expect(first.series?.points.count == 366)
    let expected = base == "EUR" ? 2.0 : base == "USD" ? 0.5 : 0.02
    #expect(first.series?.points.allSatisfy { $0.value == expected } == true)
    #expect(
      first.series?.source
        == .init(provider: .frankfurter, observation: .dailyReference, timeZone: .gmt))
    let urls = await client.urls
    #expect(urls.count == 1)
    let url = try #require(urls.first)
    #expect(url.host == "api.frankfurter.dev")
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.first { $0.name == "base" }?.value == "EUR")
    #expect(
      query.first { $0.name == "quotes" }?.value
        == Set([base, quote]).subtracting(["EUR"]).sorted().joined(separator: ","))
    #expect(query.first { $0.name == "from" }?.value == "2025-10-15")
    #expect(query.first { $0.name == "to" }?.value == "2026-10-15")
    #expect(query.first { $0.name == "providers" }?.value == "ECB")
    #expect(!query.contains { $0.name == "group" })
    let fresh = await HistoryService(directory: directory, client: client)
      .load(base: base, quote: quote, range: .year, now: now.addingTimeInterval(60))
    #expect(fresh.series?.points == first.series?.points)
    #expect(fresh.series?.source == first.series?.source)
    #expect(fresh.series?.fetchedAt == first.series?.fetchedAt)
    #expect(await client.urls.count == 1)
    let cacheFile = directory.appendingPathComponent("history-v3-\(base)-\(quote)-365.json")
    let saved = try Data(contentsOf: cacheFile)
    await client.fail()
    let stale = await service.load(
      base: base, quote: quote, range: .year, now: now.addingTimeInterval(86400))
    #expect(stale.issue == .usingCachedSeries)
    #expect(stale.series?.points == first.series?.points)
    #expect(stale.series?.source.provider == .frankfurter)
    #expect(stale.series?.fetchedAt == now)
    #expect(await client.urls.count == 3)
    #expect(await client.urls.allSatisfy { $0.host == "api.frankfurter.dev" })
    #expect(try Data(contentsOf: cacheFile) == saved)
  }

  @Test(arguments: [HistoryRange.week, .month, .quarter, .yearToDate])
  func allDailyFiatRangesUseOneRequest(range: HistoryRange) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = FiatHistoryHTTP()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "EUR", quote: "USD", range: range, now: try historyDate("2026-10-15T12:00:00Z"))
    #expect(result.issue == nil)
    #expect(result.series?.source.provider == .frankfurter)
    #expect(await client.urls.count == 1)
  }

  @Test(arguments: [
    "unsupported", "[]",
    "[{\"date\":\"2026-01-01\",\"base\":\"EUR\",\"quote\":\"USD\",\"rate\":2},{\"date\":\"2026-01-01\",\"base\":\"EUR\",\"quote\":\"USD\",\"rate\":3}]",
    "[{\"date\":\"2026-01-01\",\"base\":\"EUR\",\"quote\":\"USD\",\"rate\":0},{\"date\":\"2026-01-02\",\"base\":\"EUR\",\"quote\":\"USD\",\"rate\":3}]",
    "[{\"date\":\"2026-01-01\",\"base\":\"EUR\",\"quote\":\"USD\",\"rate\":2}]",
    "[{\"date\":\"2026-01-01\",\"base\":\"EUR\",\"quote\":\"USD\",\"rate\":2},{\"date\":\"2026-01-02\",\"base\":\"USD\",\"quote\":\"EUR\",\"rate\":3}]",
    "[{\"date\":\"2025-12-31\",\"base\":\"EUR\",\"quote\":\"USD\",\"rate\":2},{\"date\":\"2026-01-02\",\"base\":\"EUR\",\"quote\":\"USD\",\"rate\":3}]"
  ])
  func unusableRangeFallsBackToDatedPublications(response: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = FiatHistoryHTTP(response: response)
    let now = try historyDate("2026-01-03T12:00:00Z")
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: "EUR", quote: "USD", range: .yearToDate, now: now)
    #expect(first.issue == nil)
    #expect(first.series?.source.provider == .fawaz)
    #expect(first.series?.points.count == 3)
    #expect(await client.urls.count == 5)
    let fresh = await service.load(base: "EUR", quote: "USD", range: .yearToDate, now: now)
    #expect(fresh.series?.points == first.series?.points)
    #expect(fresh.series?.source == first.series?.source)
    #expect(fresh.series?.fetchedAt == first.series?.fetchedAt)
    #expect(await client.urls.count == 5)
    let expired = await service.load(
      base: "EUR", quote: "USD", range: .yearToDate, now: now.addingTimeInterval(21601))
    #expect(expired.issue == nil)
    #expect(expired.series?.source.provider == .fawaz)
    #expect(expired.series?.fetchedAt == now.addingTimeInterval(21601))
    #expect(await client.urls.count == 7)
  }

  @Test(arguments: [("GGP", "USD"), ("GBP", "IMP"), ("JEP", "GGP")])
  func sterlingParityUsesObservedPublicationDates(base: String, quote: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = FiatHistoryHTTP()
    let result = await HistoryService(directory: directory, client: client)
      .load(
        base: base, quote: quote, range: .yearToDate, now: try historyDate("2026-01-03T12:00:00Z"))
    #expect(
      result.series?.points.map(\.value) == Array(repeating: quote == "USD" ? 2.0 : 1.0, count: 3))
    #expect(await client.urls.count == 1)
  }

  @Test(arguments: ["[]", "invalid JSON"])
  func aedHistoryUsesDailyCBUAfterECBUnavailable(ecbResponse: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = FiatHistoryHTTP(ecbResponse: ecbResponse)
    let now = try historyDate("2026-10-15T12:00:00Z")
    let service = HistoryService(directory: directory, client: client)
    let inverse = await service.load(base: "AED", quote: "EUR", range: .year, now: now)
    #expect(inverse.issue == nil)
    #expect(inverse.series?.points.count == 366)
    #expect(inverse.series?.points.allSatisfy { $0.value == 0.25 } == true)
    let urls = await client.urls
    #expect(urls.count == 2)
    let queries = urls.map { URLComponents(url: $0, resolvingAgainstBaseURL: false)!.queryItems! }
    #expect(queries.map { $0.first { $0.name == "providers" }!.value! } == ["ECB", "CBU"])
    #expect(queries.allSatisfy { $0.first { $0.name == "base" }?.value == "EUR" })
    #expect(queries.allSatisfy { $0.first { $0.name == "quotes" }?.value == "AED" })
    let direct = await service.load(base: "EUR", quote: "AED", range: .year, now: now)
    #expect(direct.series?.points.allSatisfy { $0.value == 4 } == true)
    #expect(await client.urls.count == 4)
  }

  @Test func nonEuroCrossUsesOnlyMatchingObservedDates() async throws {
    let client = FiatHistoryHTTP(
      ecbResponse: "[]",
      cbuResponse: """
        [{"date":"2026-01-01","base":"EUR","quote":"AED","rate":4},
         {"date":"2026-01-01","base":"EUR","quote":"USD","rate":2},
         {"date":"2026-01-02","base":"EUR","quote":"AED","rate":4.2},
         {"date":"2026-01-03","base":"EUR","quote":"AED","rate":4.4},
         {"date":"2026-01-03","base":"EUR","quote":"USD","rate":2.2}]
        """)
    let points = try await HistoryService.fetchFiatHistory(
      client: client, base: "USD", quote: "AED",
      start: try historyDate("2026-01-01T00:00:00Z"), now: try historyDate("2026-01-03T12:00:00Z"))
    #expect(points.map(\.value) == [2, 2])
    #expect(
      points.map { String($0.date.ISO8601Format().prefix(10)) } == ["2026-01-01", "2026-01-03"])
    #expect(await client.urls.count == 2)
  }

  @Test func cryptoYearRetainsEveryDailyObservation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = FiatHistoryHTTP()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "EUR", range: .year, now: try historyDate("2026-10-15T12:00:00Z"))
    #expect(result.issue == nil)
    #expect(result.series?.points.count == 366)
    #expect(result.series?.source.provider == .fawaz)
    #expect(await client.urls.count == 366)
    #expect(await client.urls.allSatisfy { $0.host == "cdn.jsdelivr.net" })
  }

  @Test func allStillUsesCompletedBundledMonthsWithoutNetwork() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = FiatHistoryHTTP()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "EUR", quote: "USD", range: .all, now: try historyDate("2026-10-15T12:00:00Z"))
    #expect(result.issue == nil)
    #expect(result.series?.source.observation == .monthlyReference)
    #expect(await client.urls.isEmpty)
  }
}
