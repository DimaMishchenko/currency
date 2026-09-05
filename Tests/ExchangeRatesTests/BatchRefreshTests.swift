import Foundation
import Testing

@testable import ExchangeRates

private actor BatchHTTP: HTTPClient {
  private(set) var urls: [URL] = []
  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    var rates = Dictionary(uniqueKeysWithValues: CurrencyCatalog.crypto.map { ($0, "0.25") })
    rates["EUR"] = "1"
    return try JSONSerialization.data(withJSONObject: ["data": ["currency": "EUR", "rates": rates]])
  }
}

@Suite struct BatchRefreshTests {
  @Test func wholeCryptoCatalogUsesOneRequest() async throws {
    let client = BatchHTTP()
    let quotes = try await CoinbaseProvider(client: client).fetch()
    #expect(Set(quotes.keys) == CurrencyCatalog.crypto)
    #expect(
      await client.urls.map(\.absoluteString) == [
        "https://api.coinbase.com/v2/exchange-rates?currency=EUR"
      ])
  }

  @Test func batchOverlayFallsBackAndCannotLeakIntoDailyCache() async throws {
    let time = Date(timeIntervalSince1970: 1_767_355_200)
    let daily = ExchangeRate(1, published: "2026-01-02", source: .init(provider: .fawaz))
    let live = ExchangeRate(
      2, published: "2026-01-02", source: .init(provider: .coinbase, observation: .exchangeRate),
      retrievedAt: time)
    let previous = RateSnapshot(quotes: ["BTC": live], checkedAt: time)
    let service = RateService(
      fiat: StubRateProvider(quotes: nil), daily: StubRateProvider(quotes: ["BTC": daily]),
      crypto: StubRateProvider(quotes: nil))
    let failed = await service.refresh(previous: previous, now: time.addingTimeInterval(60))
    for merged in [previous.merging(failed.snapshot), failed.snapshot.merging(previous)] {
      #expect(merged.quotes["BTC"] == daily)
      #expect(merged.dailyQuotes?["BTC"] == daily)
    }
    let offline = await RateService(
      fiat: StubRateProvider(quotes: nil), daily: StubRateProvider(quotes: nil), crypto: nil
    )
    .refresh(previous: previous)
    #expect(offline.snapshot.quotes["BTC"] == nil)
    let restored = try JSONDecoder().decode(ExchangeRate.self, from: JSONEncoder().encode(live))
    #expect(restored == live)
    #expect(restored.observedAt == nil)
  }

  @Test func missingBatchAssetUsesItsDailyRate() async {
    let now = Date()
    let daily = ExchangeRate(1, published: "2026-01-02", source: .init(provider: .fawaz))
    let live = ExchangeRate(
      2, published: "2026-01-02", source: .init(provider: .coinbase, observation: .exchangeRate),
      retrievedAt: now)
    let result = await RateService(
      fiat: StubRateProvider(quotes: nil),
      daily: StubRateProvider(quotes: ["BTC": daily, "ADA": daily]),
      crypto: StubRateProvider(quotes: ["BTC": live])
    )
    .refresh(previous: RateSnapshot(), now: now)
    #expect(result.snapshot.quotes["BTC"] == live)
    #expect(result.snapshot.quotes["ADA"] == daily)
    #expect(result.warning == .partialCryptoFallback)
    let saved = RateSnapshot().merging(result.snapshot)
    #expect(saved.quotes["BTC"] == live)
    #expect(saved.dailyQuotes?["BTC"] == daily)
  }
}
