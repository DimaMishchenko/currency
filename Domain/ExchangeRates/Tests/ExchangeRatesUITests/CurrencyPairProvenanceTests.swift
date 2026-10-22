import ExchangeRates
import ExchangeRatesUI
import Foundation
import Testing

@Suite struct CurrencyPairProvenanceTests {
  private let locale = Locale(identifier: "en_US")
  private let day = "2026-10-14"

  private func snapshot(usd: Decimal = 2, ethAnchor: Decimal = 2) -> RateSnapshot {
    func crypto(price: Decimal, anchor: Decimal) -> ExchangeRate {
      ExchangeRate(
        anchor / price, published: day,
        source: .init(
          provider: .coinMetrics, observation: .minuteReference, timeZone: .gmt,
          conversion: .init(
            provider: .fawaz, published: day, value: anchor, base: "EUR", quote: "USD")),
        observedAt: Date(timeIntervalSince1970: 1_792_000_000))
    }
    return RateSnapshot(quotes: [
      "BTC": crypto(price: 100, anchor: 2), "ETH": crypto(price: 50, anchor: ethAnchor),
      "USD": ExchangeRate(
        usd, published: day, source: .init(provider: .fawaz, observation: .dailyRate)),
      "EUR": ExchangeRate(
        1, published: day, source: .init(provider: .fawaz, observation: .dailyRate)),
      "GBP": ExchangeRate(
        0.8, published: day, source: .init(provider: .fawaz, observation: .dailyRate))
    ])
  }

  @Test(arguments: [("BTC", "USD"), ("USD", "BTC"), ("BTC", "ETH"), ("ETH", "BTC")])
  func canceledAnchorsDescribeOriginalReferencesWithoutApproximation(from: String, to: String) {
    let value = snapshot()
    let text = CurrencyDisplay.details(value, from: from, to: to, locale: locale)
    #expect(text.contains("Coin Metrics · minute reference prices"))
    #expect(!text.contains("approximate conversion"))
    #expect(!text.contains("Approximate conversion:"))
    #expect(value.quotes["BTC"]?.source.conversion?.value == 2)
    #expect(value.quotes["BTC"]?.observedAt != nil)
  }

  @Test(arguments: [("BTC", "EUR"), ("EUR", "BTC")])
  func actualDailyFXConversionKeepsItsApproximationAndReference(from: String, to: String) {
    let text = CurrencyDisplay.details(snapshot(), from: from, to: to, locale: locale)
    #expect(text.contains("approximate conversion"))
    #expect(text.contains("Approximate conversion: 1 EUR = 2 USD"))
  }

  @Test(arguments: [("BTC", "ETH"), ("ETH", "BTC"), ("BTC", "USD"), ("USD", "BTC")])
  func mismatchedAnchorsRemainApproximate(from: String, to: String) {
    let text = CurrencyDisplay.details(
      snapshot(usd: 3, ethAnchor: 3), from: from, to: to, locale: locale)
    #expect(text.contains("approximate conversion"))
    #expect(text.contains("Approximate conversion:"))
  }

  @Test func fiatDirectReferencesHaveNoApproximation() {
    let text = CurrencyDisplay.details(snapshot(), from: "USD", to: "EUR", locale: locale)
    #expect(text.contains("Fawaz · daily"))
    #expect(!text.contains("approximate"))
  }

  @Test(arguments: [("BTC", "GBP"), ("GBP", "BTC")])
  func sterlingPresentationRemainsUnchanged(from: String, to: String) {
    let text = CurrencyDisplay.details(snapshot(), from: from, to: to, locale: locale)
    #expect(text.contains("Coin Metrics · minute reference prices · approximate conversion · GMT"))
    #expect(text.contains("Approximate conversion: 1 EUR = 2 USD"))
  }

  @Test func compactCurrentQuoteProvenanceOmitsSourceZoneWithoutLosingFXDetails() {
    let value = snapshot()
    let text = CurrencyDisplay.details(
      value, from: "BTC", to: "GBP", locale: locale, includesTimeZone: false)
    #expect(text.contains("Coin Metrics · minute reference prices · approximate conversion"))
    #expect(text.contains("approximate conversion · Oct 14, 2026"))
    #expect(text.contains("Approximate conversion: 1 EUR = 2 USD"))
    #expect(!text.contains("GMT"))
    #expect(value.quotes["BTC"]?.source.timeZone == .gmt)
  }

  @Test func quoteRowsUseExplicitBaseRatherThanDisplayOrder() throws {
    let value = snapshot()
    let source = try #require(
      CurrencyDisplay.quoteSource(
        value, code: "BTC", base: "USD", destinations: ["BTC", "USD"]))
    #expect(source.conversion == nil)
    #expect(source.observation == .minuteReference)
    #expect(source.timeZone == .gmt)
    let mixed = try #require(
      CurrencyDisplay.quoteSource(
        value, code: "BTC", base: "BTC", destinations: ["BTC", "USD", "EUR"]))
    #expect(mixed.conversion?.value == 2)
    let canceled = try #require(
      CurrencyDisplay.quoteSource(
        value, code: "BTC", base: "BTC", destinations: ["BTC", "USD", "ETH"]))
    #expect(canceled.conversion == nil)
    #expect(value.quotes["BTC"]?.source.conversion?.value == 2)
  }

  @Test func equalNumbersFromDifferentFXPublicationsDoNotEraseApproximation() {
    var quotes = snapshot().quotes
    quotes["USD"] = ExchangeRate(2, published: "2026-10-13", source: .init(provider: .fawaz))
    let text = CurrencyDisplay.details(
      RateSnapshot(quotes: quotes), from: "BTC", to: "USD", locale: locale)
    #expect(text.contains("approximate conversion"))
  }

  @Test func directFeedSourceDoesNotAcquireFXMetadata() {
    let direct = RateSource(provider: .coinMetrics, observation: .minuteReference, timeZone: .gmt)
    let text = RateMessages.providerDescription(
      CurrencyDisplay.presentationSource(direct, snapshot: snapshot(), from: "BTC", to: "USD"),
      locale: locale)
    #expect(text == "Coin Metrics · minute reference prices · GMT")
    #expect(RateMessages.conversionDescription(direct, locale: locale) == nil)
  }

}
