import ExchangeRates
import Foundation
import Testing

@testable import ConverterFeature
@testable import CurrencySupport
@testable import RateDetailsFeature

// These are resource-integration checks: generated getter defaults deliberately lack the
// surrounding sentence, so a wrong/missing framework bundle would fail these expectations.

@Suite struct LocalizationTests {
  @Test func generatedAccessorsResolveOwningFrameworkAndSubstitutions() {
    #expect(String(localized: .Converter.sourceAccessibility("Euro")) == "Source currency, Euro")
    #expect(String(localized: .Details.unitConversion("BTC", "USD")) == "1 BTC in USD")
    #expect(
      String(localized: .Details.chartAccessibility("One week", "EUR", "USD"))
        == "One week EUR to USD history")
    #expect(
      RateMessages.providerDescription(.init(provider: .fawaz, observation: .dailyRate))
        == "Fawaz · daily")
  }
  @Test func customProviderUsesLocalizedObservationTemplate() {
    let source = RateSource(
      provider: .custom("Example feed"), observation: .monthlyReference)
    #expect(
      RateMessages.providerDescription(source, locale: Locale(identifier: "en"))
        == "Example feed · monthly reference rates")
    let daily = RateSource(provider: .coinbase, observation: .dailyClose, timeZone: .gmt)
    #expect(RateMessages.providerDescription(daily).hasPrefix("Coinbase · daily closes · "))
  }
  @Test func unsupportedLanguageFallsBackToEnglishCatalog() {
    var resource = LocalizedStringResource.Details.unitConversion("EUR", "USD")
    resource.locale = Locale(identifier: "uk_UA")
    #expect(String(localized: resource) == "1 EUR in USD")
  }
}
