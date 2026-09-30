import Foundation
import Testing

@testable import ExchangeRates

private actor PolicyProvider: RateProvider {
  private(set) var calls = 0
  let quotes: [String: ExchangeRate]?
  init(_ quotes: [String: ExchangeRate]?) { self.quotes = quotes }
  func fetch() async throws -> [String: ExchangeRate] {
    calls += 1
    guard let quotes else { throw RateError.unavailable }
    return quotes
  }
}

@Suite struct ProviderFreshnessTests {
  private let now = Date(timeIntervalSince1970: 1_767_355_200)
  private func quote(_ value: Decimal, day: String, provider: RateProviderID) -> ExchangeRate {
    ExchangeRate(value, published: day, source: .init(provider: provider, observation: .dailyRate))
  }

  @Test(arguments: [true, false])
  func successfulProviderIsNotRetriedAfterOtherProviderFails(primarySucceeds: Bool) async {
    let quotes = ["USD": quote(2, day: "2026-01-02", provider: .ecb)]
    let primary = PolicyProvider(primarySucceeds ? quotes : nil)
    let supplemental = PolicyProvider(primarySucceeds ? nil : quotes)
    let service = RateService(fiat: primary, daily: supplemental, crypto: nil)
    let first = await service.refresh(previous: RateSnapshot(), now: now)
    let second = await service.refresh(previous: first.snapshot, now: now.addingTimeInterval(60))
    #expect(second.warning == nil)
    #expect(await primary.calls == (primarySucceeds ? 1 : 2))
    #expect(await supplemental.calls == (primarySucceeds ? 2 : 1))
  }

  @Test func newerSupplementalPublicationCannotDisplaceFreshPrimary() async {
    let primary = PolicyProvider(["USD": quote(2, day: "2026-01-01", provider: .ecb)])
    let supplemental = PolicyProvider(["USD": quote(3, day: "2026-01-02", provider: .fawaz)])
    let initial = await RateService(fiat: primary, daily: supplemental, crypto: nil)
      .refresh(previous: RateSnapshot(), now: now)
    #expect(initial.snapshot.quotes["USD"]?.value == 2)
    let expired = await RateService(fiat: PolicyProvider(nil), daily: supplemental, crypto: nil)
      .refresh(previous: initial.snapshot, now: now.addingTimeInterval(21600))
    #expect(expired.snapshot.quotes["USD"]?.value == 3)
    for merged in [
      initial.snapshot.merging(expired.snapshot), expired.snapshot.merging(initial.snapshot)
    ] {
      #expect(merged.quotes["USD"]?.value == 3)
      #expect(merged.fiatFetchedAt == now)
      #expect(merged.fiatQuotes?["USD"]?.cachedAt == now)
    }
  }

  @Test(arguments: [true, false])
  func omittedPrimaryAssetKeepsItsOwnFreshnessAcrossPartialSuccess(primaryIsFresh: Bool) async {
    let priorTime = now.addingTimeInterval(primaryIsFresh ? -60 : -21600)
    let primaryGold = quote(2, day: "2026-01-01", provider: .frankfurter)
    let prior = RateSnapshot(
      quotes: ["XAU": primaryGold], fetchedAt: priorTime,
      dailyQuotes: ["XAU": primaryGold], dailyFetchedAt: priorTime)
    let primary = PolicyProvider(["EUR": quote(1, day: "2026-01-02", provider: .ecb)])
    let supplemental = PolicyProvider(["XAU": quote(3, day: "2026-01-02", provider: .fawaz)])
    let refreshed = await RateService(fiat: primary, daily: supplemental, crypto: nil)
      .refresh(previous: prior, force: true, now: now)
    #expect(refreshed.snapshot.fiatFetchedAt == now)
    #expect(refreshed.snapshot.fiatQuotes?["XAU"]?.cachedAt == priorTime)
    for snapshot in [
      refreshed.snapshot, prior.merging(refreshed.snapshot), refreshed.snapshot.merging(prior)
    ] {
      #expect(snapshot.quotes["XAU"]?.value == (primaryIsFresh ? 2 : 3))
      #expect(snapshot.quotes["XAU"]?.source.provider == (primaryIsFresh ? .frankfurter : .fawaz))
      #expect(snapshot.fiatQuotes?["XAU"]?.cachedAt == priorTime)
    }
  }

  @Test func laterFailedAttemptPreservesNewerEqualPublicationRetrieval() throws {
    let recent = now.addingTimeInterval(60)
    let latestAttempt = now.addingTimeInterval(120)
    func cachedQuote(_ value: Decimal, provider: RateProviderID, at timestamp: Date) -> ExchangeRate
    {
      ExchangeRate(
        value, published: "2026-01-02",
        source: .init(provider: provider, observation: .dailyRate), cachedAt: timestamp)
    }
    let oldPrimary = ["USD": cachedQuote(2, provider: .ecb, at: now)]
    let newPrimary = ["USD": cachedQuote(3, provider: .ecb, at: recent)]
    let oldSupplemental = ["BTC": cachedQuote(4, provider: .fawaz, at: now)]
    let newSupplemental = ["BTC": cachedQuote(5, provider: .fawaz, at: recent)]
    let success = RateSnapshot(
      quotes: newPrimary.merging(newSupplemental) { _, incoming in incoming }, fetchedAt: recent,
      dailyQuotes: newPrimary.merging(newSupplemental) { _, incoming in incoming },
      checkedAt: recent, fiatFetchedAt: recent, supplementalFetchedAt: recent,
      fiatQuotes: newPrimary, supplementalQuotes: newSupplemental)
    let failure = RateSnapshot(
      quotes: oldPrimary.merging(oldSupplemental) { _, incoming in incoming }, fetchedAt: now,
      dailyQuotes: oldPrimary.merging(oldSupplemental) { _, incoming in incoming },
      checkedAt: latestAttempt, fiatFetchedAt: now, supplementalFetchedAt: now,
      fiatQuotes: oldPrimary, supplementalQuotes: oldSupplemental)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = RateCache(directory: directory)
    for merged in [success.merging(failure), failure.merging(success)] {
      #expect(merged.quotes["USD"] == newPrimary["USD"])
      #expect(merged.quotes["BTC"] == newSupplemental["BTC"])
      #expect(merged.dailyQuotes?["USD"] == newPrimary["USD"])
      #expect(merged.fiatQuotes == newPrimary)
      #expect(merged.supplementalQuotes == newSupplemental)
      #expect(merged.fiatFetchedAt == recent && merged.supplementalFetchedAt == recent)
      #expect(merged.checkedAt == latestAttempt)
      try cache.save(merged)
      let saved = cache.load()
      #expect(saved.fiatQuotes == newPrimary && saved.supplementalQuotes == newSupplemental)
      #expect(saved.quotes == merged.quotes && saved.dailyQuotes == merged.dailyQuotes)
    }
  }

  @Test func legacySnapshotDecodesWithoutProviderFreshnessFields() throws {
    let snapshot = RateSnapshot(
      quotes: ["USD": quote(2, day: "2026-01-02", provider: .ecb)], fetchedAt: now,
      dailyFetchedAt: now)
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(RateSnapshot.self, from: data)
    #expect(decoded.fiatFetchedAt == nil && decoded.supplementalFetchedAt == nil)
    #expect(decoded.quotes["USD"]?.value == 2)
  }
}
