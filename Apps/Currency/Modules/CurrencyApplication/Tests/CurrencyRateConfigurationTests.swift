import Conversion
import CurrencyApplication
import ExchangeRates
import Foundation
import LocalCurrency
import Testing

struct CurrencyRateConfigurationTests {
  @Test func allExecutablesShareTheBuildFlagAndCadence() {
    #if CURRENCY_DISABLE_COINBASE
      #expect(!CurrencyRateConfiguration.coinbaseEnabled)
      #expect(CurrencyRateConfiguration.policy == .daily)
      #expect(CurrencyRateConfiguration.foregroundRefreshInterval == 21_600)
      #expect(CurrencyRateConfiguration.widgetRefreshInterval == 21_600)
    #else
      #expect(CurrencyRateConfiguration.coinbaseEnabled)
      #expect(CurrencyRateConfiguration.policy == .coinbaseEnhanced)
      #expect(CurrencyRateConfiguration.foregroundRefreshInterval == 60)
      #expect(CurrencyRateConfiguration.widgetRefreshInterval == 1_800)
    #endif
  }
  @Test(arguments: [RateProviderPolicy.daily, .coinbaseEnhanced])
  func headlessConversionsRespectProviderAttemptCadence(policy: RateProviderPolicy) async throws {
    let now = Date.now
    let attempts = ProviderAttemptCounter()
    let snapshot = RateSnapshot(
      quotes: [
        "EUR": .init(1, published: "2026-10-09", source: .init(provider: .fawaz)),
        "USD": .init(2, published: "2026-10-09", source: .init(provider: .fawaz))
      ], fetchedAt: now, checkedAt: now.addingTimeInterval(-1_800))
    let action = ConversionAction(
      dependencies: .init(
        readInput: { ConverterState() }, readLocal: { (nil, .notDetermined) },
        readRates: { snapshot },
        refresh: { _ in
          await attempts.record()
          return RefreshResult(snapshot: snapshot, warning: nil)
        }, now: { now }, refreshInterval: policy.refreshInterval))
    let request = try action.request(amount: "10", source: "EUR", destination: "USD")
    let result = try await action.perform(request)
    #expect(result.results.first?.amount == "20")
    #expect(await attempts.count == (policy == .coinbaseEnhanced ? 1 : 0))
  }

}

private actor ProviderAttemptCounter {
  private(set) var count = 0
  func record() { count += 1 }
}
