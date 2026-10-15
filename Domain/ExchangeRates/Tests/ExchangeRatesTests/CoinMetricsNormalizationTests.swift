import Foundation
import Testing

@testable import ExchangeRates

private let normalizationNow = Date(timeIntervalSince1970: 1_767_355_200)

private func normalizationUSD(_ value: Decimal, day: String) -> ExchangeRate {
  ExchangeRate(value, published: day, source: .init(provider: .fawaz), cachedAt: normalizationNow)
}

private func normalizationCrypto(anchor: Decimal, day: String) -> ExchangeRate {
  ExchangeRate(
    anchor / 100, published: "2026-01-02",
    source: .init(
      provider: .coinMetrics, observation: .minuteReference,
      conversion: .init(provider: .fawaz, published: day, value: anchor, base: "EUR", quote: "USD")),
    observedAt: normalizationNow.addingTimeInterval(-60), retrievedAt: normalizationNow)
}

private func normalizationPrevious(live: Bool = false) -> RateSnapshot {
  let usd = normalizationUSD(2, day: "2026-01-01")
  var quotes = ["USD": usd]
  if live { quotes["BTC"] = normalizationCrypto(anchor: 2, day: "2026-01-01") }
  return RateSnapshot(
    quotes: quotes, fetchedAt: normalizationNow,
    dailyQuotes: ["USD": usd], dailyFetchedAt: normalizationNow,
    supplementalFetchedAt: normalizationNow, supplementalQuotes: ["USD": usd])
}

private actor NormalizationGate: RateProvider {
  let quotes: [String: ExchangeRate]
  private var released = false
  private var waiter: CheckedContinuation<Void, Never>?
  init(quotes: [String: ExchangeRate]) { self.quotes = quotes }
  func fetch() async throws -> [String: ExchangeRate] {
    if !released { await withCheckedContinuation { waiter = $0 } }
    return quotes
  }
  func release() {
    released = true
    waiter?.resume()
    waiter = nil
  }
}

@Suite struct CoinMetricsNormalizationTests {
  private func expectUSD100(_ snapshot: RateSnapshot, anchor: Decimal, day: String) {
    #expect(snapshot.convert(1, from: "BTC", to: "USD") == 100)
    #expect(snapshot.quotes["BTC"]?.source.conversion?.value == anchor)
    #expect(snapshot.quotes["BTC"]?.source.conversion?.published == day)
    #expect(snapshot.quotes["BTC"]?.observedAt == normalizationNow.addingTimeInterval(-60))
    #expect(snapshot.quotes["BTC"]?.retrievedAt == normalizationNow)
  }

  @Test func refreshUsesFreshCachedDailyUSDWhenProviderFXPublicationAdvances() async {
    let result = await RateService(
      fiat: StubRateProvider(quotes: nil), daily: StubRateProvider(quotes: nil),
      crypto: StubRateProvider(quotes: ["BTC": normalizationCrypto(anchor: 4, day: "2026-01-02")])
    )
    .refresh(previous: normalizationPrevious(), now: normalizationNow)
    #expect(result.snapshot.quotes["BTC"]?.value == Decimal(string: "0.02"))
    expectUSD100(result.snapshot, anchor: 2, day: "2026-01-01")
  }

  @Test func bootstrapRebasesEachDeliveryAsDailyAnchorArrives() async throws {
    let daily = NormalizationGate(quotes: ["USD": normalizationUSD(4, day: "2026-01-02")])
    let service = RateService(
      fiat: StubRateProvider(quotes: nil), daily: daily,
      crypto: StubRateProvider(quotes: ["BTC": normalizationCrypto(anchor: 4, day: "2026-01-02")]))
    var sawCached = false
    var sawUpdated = false
    for await update in await service.bootstrap(
      previous: normalizationPrevious(), now: normalizationNow)
    where update.snapshot.quotes["BTC"] != nil {
      let updated = update.snapshot.quotes["USD"]?.value == 4
      expectUSD100(
        update.snapshot, anchor: updated ? 4 : 2, day: updated ? "2026-01-02" : "2026-01-01")
      if updated { sawUpdated = true } else { sawCached = true; await daily.release() }
    }
    #expect(sawCached)
    #expect(sawUpdated)
  }

  @Test func bootstrapPendingPreviousLiveQuoteRebasesToNewDailyAnchor() async {
    let crypto = NormalizationGate(quotes: [
      "BTC": normalizationCrypto(anchor: 4, day: "2026-01-02")
    ])
    let service = RateService(
      fiat: StubRateProvider(quotes: nil),
      daily: StubRateProvider(quotes: ["USD": normalizationUSD(4, day: "2026-01-02")]),
      crypto: crypto)
    var sawUpdatedBeforeCompletion = false
    for await update in await service.bootstrap(
      previous: normalizationPrevious(live: true), now: normalizationNow)
    where update.snapshot.quotes["USD"]?.value == 4 {
      expectUSD100(update.snapshot, anchor: 4, day: "2026-01-02")
      if !update.isFinal { sawUpdatedBeforeCompletion = true; await crypto.release() }
    }
    #expect(sawUpdatedBeforeCompletion)
  }

  @Test func cachedPolicyReadRealignsLaterDailyPublicationWithoutChangingMarketTime() {
    let newUSD = normalizationUSD(4, day: "2026-01-02")
    let staleAnchor = normalizationCrypto(anchor: 2, day: "2026-01-01")
    let snapshot = RateSnapshot(
      quotes: ["USD": newUSD, "BTC": staleAnchor], fetchedAt: normalizationNow,
      dailyQuotes: ["USD": newUSD], dailyFetchedAt: normalizationNow)
    let aligned = RateProviderPolicy.intradayEnhanced.filter(snapshot)
    expectUSD100(aligned, anchor: 4, day: "2026-01-02")
    #expect(RateProviderPolicy.intradayEnhanced.filter(aligned).quotes == aligned.quotes)
  }
}
