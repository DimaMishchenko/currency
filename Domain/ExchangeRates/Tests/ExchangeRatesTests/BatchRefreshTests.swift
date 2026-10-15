import Foundation
import Testing

@testable import ExchangeRates

private actor BatchHTTP: HTTPClient {
  private(set) var urls: [URL] = []
  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    if url.host == "community-api.coinmetrics.io" {
      let rows = CurrencyCatalog.crypto.map {
        [
          "asset": $0.lowercased(), "time": Date().addingTimeInterval(-60).ISO8601Format(),
          "ReferenceRateUSD": "8"
        ]
      }
      return try JSONSerialization.data(withJSONObject: ["data": rows])
    }
    return Data(
      "{\"date\":\"\(String(Date().ISO8601Format().prefix(10)))\",\"eur\":{\"usd\":2,\"btc\":0.25}}"
        .utf8)
  }
}

@Suite struct BatchRefreshTests {
  @Test func wholeCryptoCatalogUsesOneMetricsRequestAndOneDailyFXRequest() async throws {
    let client = BatchHTTP()
    let quotes = try await CoinMetricsProvider(client: client).fetch()
    #expect(Set(quotes.keys) == CurrencyCatalog.crypto)
    #expect(quotes.values.allSatisfy { $0.value == Decimal(string: "0.25") })
    #expect(await client.urls.count == 2)
    #expect(await client.urls.filter { $0.host == "community-api.coinmetrics.io" }.count == 1)
  }

  @Test func batchOverlayFallsBackAndCannotLeakIntoDailyCache() async throws {
    let time = Date(timeIntervalSince1970: 1_767_355_200)
    let daily = ExchangeRate(1, published: "2026-01-02", source: .init(provider: .fawaz))
    let live = ExchangeRate(
      2, published: "2026-01-02",
      source: .init(provider: .coinMetrics, observation: .minuteReference),
      retrievedAt: time)
    let previous = RateSnapshot(quotes: ["BTC": live], checkedAt: time)
    let service = RateService(
      fiat: StubRateProvider(quotes: nil), daily: StubRateProvider(quotes: ["BTC": daily]),
      crypto: StubRateProvider(quotes: nil))
    let refreshedAt = time.addingTimeInterval(60)
    let cachedDaily = ExchangeRate(
      1, published: "2026-01-02", source: .init(provider: .fawaz),
      cachedAt: refreshedAt)
    let failed = await service.refresh(previous: previous, now: refreshedAt)
    for merged in [previous.merging(failed.snapshot), failed.snapshot.merging(previous)] {
      #expect(merged.quotes["BTC"] == cachedDaily)
      #expect(merged.dailyQuotes?["BTC"] == cachedDaily)
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
      2, published: "2026-01-02",
      source: .init(provider: .coinMetrics, observation: .minuteReference),
      retrievedAt: now)
    let result = await RateService(
      fiat: StubRateProvider(quotes: nil),
      daily: StubRateProvider(quotes: ["BTC": daily, "ADA": daily]),
      crypto: StubRateProvider(quotes: ["BTC": live])
    )
    .refresh(previous: RateSnapshot(), now: now)
    let cachedDaily = ExchangeRate(
      1, published: "2026-01-02", source: .init(provider: .fawaz),
      cachedAt: now)
    #expect(result.snapshot.quotes["BTC"] == live)
    #expect(result.snapshot.quotes["ADA"] == cachedDaily)
    #expect(result.warning == .partialCryptoFallback)
    let saved = RateSnapshot().merging(result.snapshot)
    #expect(saved.quotes["BTC"] == live)
    #expect(saved.dailyQuotes?["BTC"] == cachedDaily)
  }
}
