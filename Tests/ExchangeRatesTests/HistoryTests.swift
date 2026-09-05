import Foundation
import Testing

@testable import ExchangeRates

private let day = "2026-01-02"

private actor LongHistoryHTTP: HTTPClient {
  var urls: [URL] = []
  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    guard let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      let raw = query.first(where: { $0.name == "start" })?.value,
      let date = ISO8601DateFormatter().date(from: raw)
    else { throw RateError.invalidData }
    let start = date.timeIntervalSince1970
    return try JSONEncoder()
      .encode([[start + 86400, 1, 5, 2, 3, 1], [start + 172800, 1, 5, 2, 4, 1]])
  }
}
private actor MaxFiatHTTP: HTTPClient {
  var urls: [URL] = []
  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    return Data(
      #"[{"date":"1999-01-01","base":"EUR","quote":"USD","rate":1.1},{"date":"2026-01-01","base":"EUR","quote":"USD","rate":1.2}]"#
        .utf8)
  }
}
private actor HistoryHTTP: HTTPClient {
  var calls = 0
  func get(_ url: URL) async throws -> Data {
    calls += 1
    if calls > 1 { throw RateError.http(429) }
    return Data(
      #"[{"date":"2026-01-02","base":"USD","quote":"EUR","rate":0.8},{"date":"2026-01-03","base":"USD","quote":"EUR","rate":0.9}]"#
        .utf8)
  }
}

@Suite struct HistoryTests {
  @Test func longHistoryWindowsAndMonthlyCloses() {
    let start = Date(timeIntervalSince1970: 0)
    let end = start.addingTimeInterval(366 * 86400)
    let windows = HistoryService.candleWindows(start: start, end: end)
    #expect(windows.count == 2)
    #expect(windows.first?.start == start)
    #expect(windows.last?.end == end)
    #expect(windows[0].end == windows[1].start)
    #expect(windows.allSatisfy { $0.end.timeIntervalSince($0.start) <= 299 * 86400 })
    let points = [
      HistoryPoint(date: start, value: 1),
      HistoryPoint(date: start.addingTimeInterval(86400), value: 2),
      HistoryPoint(date: start.addingTimeInterval(40 * 86400), value: 3)
    ]
    #expect(HistoryService.monthlyCloses(points.reversed()).map(\.value) == [2, 3])
  }
  @Test func yearlyCryptoFetchesEveryPageAndCaches() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = LongHistoryHTTP()
    let service = HistoryService(directory: directory, client: client)
    let now = try #require(ISO8601DateFormatter().date(from: "2026-01-02T00:00:00Z"))
    let result = await service.load(base: "BTC", quote: "USD", range: .year, now: now)
    #expect(result.series?.points.count == 4)
    #expect(await client.urls.count == 2)
    _ = await service.load(base: "BTC", quote: "USD", range: .year, now: now)
    #expect(await client.urls.count == 2)
  }
  @Test func maxFiatRequestsMonthlyHistoryAndCachesForOneDay() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MaxFiatHTTP()
    let service = HistoryService(directory: directory, client: client)
    let now = Date()
    let result = await service.load(base: "EUR", quote: "USD", range: .all, now: now)
    #expect(result.series?.points.count == 2)
    let url = try #require(await client.urls.first)
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.contains(URLQueryItem(name: "from", value: "1948-01-01")))
    #expect(query.contains(URLQueryItem(name: "group", value: "month")))
    _ = await service.load(
      base: "EUR", quote: "USD", range: .all, now: now.addingTimeInterval(43200))
    #expect(await client.urls.count == 1)
  }
  @Test func historySortsAndUsesCompletedClose() throws {
    let rows = Data("[[172800,1,9,3,5,20],[86400,1,9,3,4,20],[259200,1,9,3,8,20]]".utf8)
    let points = try HistoryService.decodeCandles(
      rows, start: Date(timeIntervalSince1970: 86400), end: Date(timeIntervalSince1970: 300000))
    #expect(points.map(\.value) == [4, 5])
    #expect(throws: (any Error).self) {
      try HistoryService.decodeCandles(Data("[[1,2]]".utf8), start: .distantPast, end: .now)
    }
    let fiat = Data(
      #"[{"date":"2026-01-03","base":"USD","quote":"EUR","rate":0.9},{"date":"2026-01-02","base":"USD","quote":"EUR","rate":0.8}]"#
        .utf8)
    #expect(
      try HistoryService.decodeFiat(fiat, base: "USD", quote: "EUR").map(\.value) == [0.8, 0.9])
  }
  @Test func historyCachesAndFallsBackOffline() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = HistoryHTTP()
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: "USD", quote: "EUR", range: .month)
    #expect(first.series?.points.count == 2)
    _ = await service.load(base: "USD", quote: "EUR", range: .month)
    #expect(await client.calls == 1)
    let offline = await service.load(
      base: "USD", quote: "EUR", range: .month, now: Date().addingTimeInterval(86400))
    #expect(offline.series?.points == first.series?.points)
    #expect(offline.issue != nil)
  }
}
