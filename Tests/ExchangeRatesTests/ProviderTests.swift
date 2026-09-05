import Foundation
import Testing

@testable import ExchangeRates

private let day = "2026-01-02"

private actor FallbackHTTP: HTTPClient {
  var calls = 0
  func get(_ url: URL) async throws -> Data {
    calls += 1
    if calls == 1 { throw RateError.http(503) }
    return Data(#"{"date":"2026-01-02","eur":{"usd":1.2,"btc":0.00002}}"#.utf8)
  }
}

@Suite struct ProviderTests {
  @Test func frankfurterValidationAndExpandedCatalog() throws {
    let data = Data(
      #"[{"date":"2026-01-02","base":"EUR","quote":"USD","rate":1.2},{"date":"2026-01-02","base":"EUR","quote":"UAH","rate":50}]"#
        .utf8)
    let quotes = try FrankfurterProvider.decode(data)
    #expect(quotes["UAH"]?.value == 50)
    #expect(quotes["EUR"]?.value == 1)
    #expect(throws: (any Error).self) {
      try FrankfurterProvider.decode(
        Data(#"[{"date":"2026-01-02","base":"USD","quote":"EUR","rate":1}]"#.utf8))
    }
  }
  @Test func frankfurterFailsToDirectECB() async throws {
    let fallback = StubRateProvider(quotes: [
      "EUR": ExchangeRate(1, published: day, source: .init(provider: .custom("ECB")))
    ])
    let rates = try await FallbackRateProvider(
      primary: StubRateProvider(quotes: nil), fallback: fallback
    )
    .fetch()
    #expect(rates["EUR"]?.source.provider == .custom("ECB"))
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
  @Test func alternateCDN() async throws {
    let client = FallbackHTTP()
    let quotes = try await FawazProvider(client: client).fetch()
    #expect(quotes["BTC"] != nil)
    #expect(await client.calls == 2)
  }
}
