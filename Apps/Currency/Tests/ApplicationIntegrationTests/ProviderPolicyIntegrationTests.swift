import AppearancePreferences
import CurrencyApplication
import ExchangeRates
import Foundation
import Testing

@MainActor
struct ProviderPolicyIntegrationTests {
  @Test(arguments: [RateProviderPolicy.daily, .coinbaseEnhanced])
  func everyPhoneEntryUsesTheSelectedPolicy(policy: RateProviderPolicy) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer {
      try? FileManager.default.removeItem(at: directory)
      defaults.removePersistentDomain(forName: suite)
    }
    let now = Date.now
    let day = now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    let daily: [String: ExchangeRate] = [
      "EUR": .init(1, published: day, source: .init(provider: .fawaz), cachedAt: now),
      "BTC": .init(0.01, published: day, source: .init(provider: .fawaz), cachedAt: now)
    ]
    var quotes = daily
    quotes["BTC"] = .init(
      0.02, published: day, source: .init(provider: .coinbase, observation: .exchangeRate),
      retrievedAt: now)
    try RateCache(directory: directory)
      .save(
        .init(
          quotes: quotes, fetchedAt: now, dailyQuotes: daily, dailyFetchedAt: now,
          checkedAt: now, supplementalFetchedAt: now, supplementalQuotes: daily))
    let composition = AppComposition(
      directory: directory, appearance: AppearancePreferences(defaults: defaults),
      discoveryDefaults: defaults, policy: policy)
    _ = try composition.edit { $0.setDestinations(["BTC"]) }
    let expected: Decimal = policy == .daily ? 1 : 2
    #expect(composition.home.readRates().convert(100, from: "EUR", to: "BTC") == expected)
    #expect(
      composition.systemActions.action.dependencies.readRates()
        .convert(100, from: "EUR", to: "BTC") == expected)
    let settings = composition.settings(scene: composition.makeScene())
    #expect(settings.readState().snapshot.convert(100, from: "EUR", to: "BTC") == expected)
    #expect(settings.usesCoinbase == (policy == .coinbaseEnhanced))
    #expect(composition.details.supportsIntraday("BTC", "USD") == (policy == .coinbaseEnhanced))
    #expect(!composition.details.supportsIntraday("EUR", "USD"))
    #expect(composition.history.policy == policy)
  }
}
