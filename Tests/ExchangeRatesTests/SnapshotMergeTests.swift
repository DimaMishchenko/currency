import ExchangeRates
import Foundation
import Testing

@Suite struct SnapshotMergeTests {
  private func quote(
    _ value: Decimal, day: String = "2026-01-02", time: Double? = nil
  ) -> ExchangeRate {
    ExchangeRate(
      value, published: day, source: .init(provider: .coinbase),
      observedAt: time.map { Date(timeIntervalSince1970: $0) })
  }

  @Test func mergePreservesNewerPublicationAndObservation() {
    let earlier = RateSnapshot(
      quotes: ["USD": quote(2, day: "2026-01-03"), "BTC": quote(4, time: 30)],
      dailyQuotes: ["USD": quote(2, day: "2026-01-03"), "BTC": quote(1)],
      checkedAt: Date(timeIntervalSince1970: 40))
    let later = RateSnapshot(
      quotes: ["USD": quote(1), "BTC": quote(3, time: 20)],
      dailyQuotes: ["USD": quote(1), "BTC": quote(1)],
      checkedAt: Date(timeIntervalSince1970: 50))
    for merged in [earlier.merging(later), later.merging(earlier)] {
      #expect(merged.quotes["USD"]?.value == 2)
      #expect(merged.quotes["BTC"]?.value == 4)
      #expect(merged.dailyQuotes?["BTC"]?.value == 1)
    }
  }

  @Test func newerFailedAttemptDoesNotResurrectOldLiveOverlay() {
    let live = RateSnapshot(
      quotes: ["BTC": quote(4, time: 30)],
      dailyQuotes: ["BTC": quote(1)], checkedAt: Date(timeIntervalSince1970: 40))
    let failed = RateSnapshot(
      quotes: ["BTC": quote(1)],
      dailyQuotes: ["BTC": quote(1)], checkedAt: Date(timeIntervalSince1970: 50))
    #expect(live.merging(failed).quotes["BTC"]?.observedAt == nil)
    #expect(failed.merging(live).quotes["BTC"]?.value == 1)
  }
}
