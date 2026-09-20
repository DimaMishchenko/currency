import Foundation
import Testing

@testable import ExchangeRates

private let day = "2026-01-02"

@Suite struct RateServiceTests {
  @Test func coinbaseFailureRestoresDailyAndDailyCacheIsRetained() async {
    let daily = [
      "EUR": ExchangeRate(1, published: day, source: .init(provider: .custom("daily"))),
      "BTC": ExchangeRate(2, published: day, source: .init(provider: .custom("Fawaz · daily")))
    ]
    let live = [
      "BTC": ExchangeRate(
        3, published: day, source: .init(provider: .custom("Coinbase")), observedAt: .now)
    ]
    let fresh = await RateService(
      fiat: StubRateProvider(quotes: daily), daily: StubRateProvider(quotes: daily),
      crypto: StubRateProvider(quotes: live)
    )
    .refresh(previous: RateSnapshot())
    #expect(fresh.snapshot.quotes["BTC"]?.value == 3)
    #expect(fresh.snapshot.dailyQuotes?["BTC"]?.value == 2)
    let failed = await RateService(
      fiat: StubRateProvider(quotes: nil), daily: StubRateProvider(quotes: nil),
      crypto: StubRateProvider(quotes: nil)
    )
    .refresh(previous: fresh.snapshot)
    #expect(failed.snapshot.quotes["BTC"]?.value == 2)
    #expect(failed.snapshot.quotes["BTC"]?.observedAt == nil)
    #expect(failed.warning != nil)
  }

  @Test func fallbackAndOffline() async {
    let old = RateSnapshot(
      quotes: ["USD": ExchangeRate(2, published: day, source: .init(provider: .custom("saved")))],
      fetchedAt: Date(timeIntervalSince1970: 10))
    let offline = await RateService(
      fiat: StubRateProvider(quotes: nil), daily: StubRateProvider(quotes: nil), crypto: nil
    )
    .refresh(previous: old)
    #expect(offline.snapshot.quotes == old.quotes)
    #expect(offline.snapshot.fetchedAt == old.fetchedAt)
    #expect(offline.warning != nil)
    let result = await RateService(
      fiat: StubRateProvider(quotes: nil),
      daily: StubRateProvider(quotes: [
        "USD": ExchangeRate(
          3, published: "2026-01-03", source: .init(provider: .custom("fallback")))
      ]),
      crypto: nil
    )
    .refresh(previous: old)
    #expect(result.snapshot.quotes["USD"]?.value == 3)
  }

  @Test func newerCacheWinsAndECBPreferred() async {
    let old = RateSnapshot(quotes: [
      "USD": ExchangeRate(2, published: day, source: .init(provider: .custom("saved")))
    ])
    let older = StubRateProvider(quotes: [
      "USD": ExchangeRate(3, published: "2026-01-01", source: .init(provider: .custom("older")))
    ])
    let result = await RateService(fiat: older, daily: older, crypto: nil).refresh(previous: old)
    #expect(result.snapshot.quotes["USD"]?.value == 2)
    let primary = StubRateProvider(quotes: [
      "USD": ExchangeRate(4, published: day, source: .init(provider: .custom("ECB")))
    ])
    let preferred = await RateService(fiat: primary, daily: older, crypto: nil)
      .refresh(previous: old)
    #expect(preferred.snapshot.quotes["USD"]?.source.provider == .custom("ECB"))
  }
}
