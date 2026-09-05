import Foundation
import Testing

@testable import RateCore

private let day = "2026-01-02"

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
@Test func yearlyCryptoFetchesEveryPageAndCaches() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let client = LongHistoryHTTP()
  let service = HistoryService(directory: directory, client: client)
  let now = try #require(ISO8601DateFormatter().date(from: "2026-01-02T00:00:00Z"))
  let result = await service.load(base: "BTC", quote: "USD", days: 365, now: now)
  #expect(result.series?.points.count == 4)
  #expect(await client.urls.count == 2)
  _ = await service.load(base: "BTC", quote: "USD", days: 365, now: now)
  #expect(await client.urls.count == 2)
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
@Test func maxFiatRequestsMonthlyHistoryAndCachesForOneDay() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let client = MaxFiatHTTP(); let service = HistoryService(directory: directory, client: client)
  let now = Date()
  let result = await service.load(base: "EUR", quote: "USD", days: 0, now: now)
  #expect(result.series?.points.count == 2)
  let url = try #require(await client.urls.first)
  let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
  #expect(query.contains(URLQueryItem(name: "from", value: "1948-01-01")))
  #expect(query.contains(URLQueryItem(name: "group", value: "month")))
  _ = await service.load(base: "EUR", quote: "USD", days: 0, now: now.addingTimeInterval(43200))
  #expect(await client.urls.count == 1)
}
private struct Stub: RateProvider {
  let quotes: [String: Quote]?
  func fetch() async throws -> [String: Quote] {
    guard let quotes else { throw RateError.unavailable }; return quotes
  }
}

@Test func frankfurterValidationAndExpandedCatalog() throws {
  let data = Data(
    #"[{"date":"2026-01-02","base":"EUR","quote":"USD","rate":1.2},{"date":"2026-01-02","base":"EUR","quote":"UAH","rate":50}]"#
      .utf8)
  let quotes = try FrankfurterProvider.decode(data)
  #expect(quotes["UAH"]?.value == 50)
  #expect(quotes["EUR"]?.value == 1)
  #expect(Currency.flag("UAH") == "🇺🇦")
  #expect(Currency.flag("AED") == "🇦🇪")
  #expect(throws: (any Error).self) {
    try FrankfurterProvider.decode(
      Data(#"[{"date":"2026-01-02","base":"USD","quote":"EUR","rate":1}]"#.utf8))
  }
}
@Test func frankfurterFailsToDirectECB() async throws {
  let fallback = Stub(quotes: ["EUR": Quote(1, published: day, source: "ECB")])
  let rates = try await FiatProvider(primary: Stub(quotes: nil), fallback: fallback).fetch()
  #expect(rates["EUR"]?.source == "ECB")
}
@Test func coinbaseInversionAndStaleness() throws {
  let now = try #require(ISO8601DateFormatter().date(from: "2026-01-02T12:00:00Z"))
  let data = Data(#"{"price":"50000","time":"2026-01-02T11:59:30.000Z"}"#.utf8)
  let quote = try CoinbaseProvider.decode(data, now: now)
  #expect(quote.value == Decimal(string: "0.00002"))
  #expect(quote.observedAt != nil)
  #expect(throws: (any Error).self) {
    try CoinbaseProvider.decode(data, now: now.addingTimeInterval(7200))
  }
  #expect(throws: (any Error).self) {
    try CoinbaseProvider.decode(
      Data(#"{"price":"0","time":"2026-01-02T12:00:00Z"}"#.utf8), now: now)
  }
}
@Test func coinbaseFailureRestoresDailyAndDailyCacheIsRetained() async {
  let daily = [
    "EUR": Quote(1, published: day, source: "daily"),
    "BTC": Quote(2, published: day, source: "Fawaz · daily")
  ]
  let live = ["BTC": Quote(3, published: day, source: "Coinbase", observedAt: .now)]
  let fresh = await RateService(
    fiat: Stub(quotes: daily), daily: Stub(quotes: daily), crypto: Stub(quotes: live)
  )
  .refresh(previous: RateBook())
  #expect(fresh.book.quotes["BTC"]?.value == 3)
  #expect(fresh.book.dailyQuotes?["BTC"]?.value == 2)
  let failed = await RateService(
    fiat: Stub(quotes: nil), daily: Stub(quotes: nil), crypto: Stub(quotes: nil)
  )
  .refresh(previous: fresh.book)
  #expect(failed.book.quotes["BTC"]?.value == 2)
  #expect(failed.book.quotes["BTC"]?.observedAt == nil)
  #expect(failed.warning != nil)
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
  #expect(try HistoryService.decodeFiat(fiat, base: "USD", quote: "EUR").map(\.value) == [0.8, 0.9])
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
@Test func historyCachesAndFallsBackOffline() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let client = HistoryHTTP(); let service = HistoryService(directory: directory, client: client)
  let first = await service.load(base: "USD", quote: "EUR", days: 30)
  #expect(first.series?.points.count == 2)
  _ = await service.load(base: "USD", quote: "EUR", days: 30)
  #expect(await client.calls == 1)
  let offline = await service.load(
    base: "USD", quote: "EUR", days: 30, now: Date().addingTimeInterval(86400))
  #expect(offline.series?.points == first.series?.points)
  #expect(offline.message != nil)
}
@Test func crossRatesAndMissingCurrency() throws {
  let book = RateBook(quotes: [
    "EUR": Quote(1, published: day, source: "test"),
    "USD": Quote(2, published: day, source: "test"),
    "BTC": Quote(try #require(Decimal(string: "0.00002")), published: day, source: "test")
  ])
  #expect(book.convert(10, from: "USD", to: "EUR") == 5)
  #expect(book.convert(1, from: "BTC", to: "USD") == 100000)
  #expect(book.convert(10, from: "USD", to: "JPY") == nil)
  #expect(book.convert(10, from: "USD", to: "USD") == 10)
}
@Test func xmlParsing() throws {
  let xml = Data(
    "<gesmes:Envelope xmlns:gesmes='urn:test'><Cube><Cube time='2026-01-02'><Cube currency='USD' rate='1.25'/></Cube></Cube></gesmes:Envelope>"
      .utf8)
  let quotes = try ECBProvider.decode(xml)
  #expect(quotes["EUR"]?.value == 1)
  #expect(quotes["USD"]?.value == Decimal(string: "1.25"))
  #expect(quotes["USD"]?.published == day)
  #expect(throws: (any Error).self) { try ECBProvider.decode(Data("<Cube/>".utf8)) }
  #expect(throws: (any Error).self) {
    try ECBProvider.decode(
      Data("<Cube time='2026-01-02'><Cube currency='USD' rate='0'/></Cube>".utf8))
  }
}
@Test func dailyParsing() throws {
  let data = Data(#"{"date":"2026-01-02","eur":{"usd":1.2,"btc":0.00002,"eth":0.0003}}"#.utf8)
  let quotes = try FawazProvider.decode(data)
  #expect(quotes["BTC"]?.value == Decimal(string: "0.00002"))
  #expect(throws: (any Error).self) {
    try FawazProvider.decode(Data(#"{"date":"bad","eur":{"usd":1,"btc":1}}"#.utf8))
  }
}
@Test func fallbackAndOffline() async {
  let old = RateBook(
    quotes: ["USD": Quote(2, published: day, source: "saved")],
    fetchedAt: Date(timeIntervalSince1970: 10))
  let offline = await RateService(fiat: Stub(quotes: nil), daily: Stub(quotes: nil), crypto: nil)
    .refresh(previous: old)
  #expect(offline.book.quotes == old.quotes)
  #expect(offline.book.fetchedAt == old.fetchedAt)
  #expect(offline.warning != nil)
  let result = await RateService(
    fiat: Stub(quotes: nil),
    daily: Stub(quotes: ["USD": Quote(3, published: "2026-01-03", source: "fallback")]), crypto: nil
  )
  .refresh(previous: old)
  #expect(result.book.quotes["USD"]?.value == 3)
}
@Test func newerCacheWinsAndECBPreferred() async {
  let old = RateBook(quotes: ["USD": Quote(2, published: day, source: "saved")])
  let older = Stub(quotes: ["USD": Quote(3, published: "2026-01-01", source: "older")])
  let result = await RateService(fiat: older, daily: older, crypto: nil).refresh(previous: old)
  #expect(result.book.quotes["USD"]?.value == 2)
  let primary = Stub(quotes: ["USD": Quote(4, published: day, source: "ECB")])
  let preferred = await RateService(fiat: primary, daily: older, crypto: nil).refresh(previous: old)
  #expect(preferred.book.quotes["USD"]?.source == "ECB")
}
@Test func keypad() {
  var input = InputState(); input.press("AC"); input.press("0"); input.press(","); input.press(".");
  input.press("5")
  #expect(input.amount == "0.5")
  input.press("⌫"); input.press("⌫"); input.press("⌫")
  #expect(input.amount == "0")
  input.press("⇅"); #expect(input.from == "USD")
  for _ in 0..<30 { input.press("9") }; #expect(input.amount.count == 14)
}
@Test func cacheRoundTripAndCorruption() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = DiskStore(directory: directory)
  #expect(store.load().quotes.isEmpty)
  let book = RateBook(quotes: [
    "BTC": Quote(
      try #require(Decimal(string: "0.000012345678")), published: day, source: "daily")
  ])
  try store.save(book)
  #expect(store.load().quotes == book.quotes)
  try Data("broken".utf8).write(to: directory.appendingPathComponent("rates.json"))
  #expect(store.load().quotes.isEmpty)
}
private actor FallbackHTTP: HTTPClient {
  var calls = 0
  func get(_ url: URL) async throws -> Data {
    calls += 1
    if calls == 1 { throw RateError.http(503) }
    return Data(#"{"date":"2026-01-02","eur":{"usd":1.2,"btc":0.00002}}"#.utf8)
  }
}
@Test func alternateCDN() async throws {
  let client = FallbackHTTP()
  let quotes = try await FawazProvider(client: client).fetch()
  #expect(quotes["BTC"] != nil)
  #expect(await client.calls == 2)
}

@Test func legacyInputMigrationAndListNormalization() throws {
  let old = Data(#"{"amount":"12","from":"EUR","to":"USD"}"#.utf8)
  var input = try JSONDecoder().decode(InputState.self, from: old)
  #expect(input.destinations == ["USD", "GBP", "CZK", "JPY", "CHF", "BTC"])
  input.setDestinations(["GBP", "GBP", "EUR", "BAD", "USD"])
  #expect(input.destinations == ["GBP", "USD"])
  #expect(input.to == "GBP")
  let restored = try JSONDecoder().decode(InputState.self, from: JSONEncoder().encode(input))
  #expect(restored.destinations == ["GBP", "USD"])
}
@Test func promoteCurrencyPreservesValueAndOrder() throws {
  var input = InputState(); input.amount = "100"
  input.setDestinations(["USD", "GBP", "JPY"])
  let book = RateBook(quotes: [
    "EUR": Quote(1, published: day, source: "test"),
    "USD": Quote(try #require(Decimal(string: "1.25")), published: day, source: "test")
  ])
  input.useAsBase("USD", book: book)
  #expect(input.from == "USD")
  #expect(input.amount == "125")
  #expect(input.destinations == ["EUR", "GBP", "JPY"])
  #expect(book.convert(input.decimal, from: input.from, to: "EUR") == 100)
  let unchanged = input
  input.useAsBase("JPY", book: book)
  #expect(input == unchanged)
  input.press("⇅")
  #expect(input.from == "EUR")
  #expect(input.destinations == ["USD", "GBP", "JPY"])
}
