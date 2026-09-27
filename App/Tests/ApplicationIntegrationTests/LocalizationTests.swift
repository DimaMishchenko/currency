import ExchangeRates
import Foundation
import Testing

@testable import CurrencyDetailsUI
@testable import CurrencySelectionUI
@testable import ExchangeRatesUI
@testable import HomeUI
@testable import LocationOnboardingUI
@testable import OnboardingUI
@testable import SettingsUI
@testable import WidgetOnboardingUI
@testable import WidgetsUI

// These are resource-integration checks: generated getter defaults deliberately lack the
// surrounding sentence, so a wrong/missing framework bundle would fail these expectations.

@Suite struct LocalizationTests {
  @Test func generatedAccessorsResolveOwningFrameworkAndSubstitutions() {
    #expect(String(localized: .WidgetOnboarding.guideStep(2, 6)) == "Step 2 of 6")
    #expect(
      String(localized: .WidgetOnboarding.guideExploreWidget("Calculator", "Large"))
        == "Explore Calculator, Large")
    #expect(String(localized: .LocalCurrency.localUseLocation) == "Use my location")
    #expect(String(localized: .LocalCurrency.localAddToApp) == "Add to app")
    #expect(
      String(localized: .LocalCurrency.localReadyAppCurrency("CZK"))
        == "Add Local to follow the currency around you. Currently CZK.")
    #expect(String(localized: .CurrencySelection.baseCurrency) == "Base currency")
    #expect(String(localized: .CurrencySelection.localCurrency) == "Local currency")
    #expect(
      String(localized: .CurrencySelection.localCurrencyName("Czech Koruna"))
        == "Local currency · Czech Koruna")
    #expect(String(localized: .WidgetPresentation.clear) == "Clear")
    #expect(
      String(localized: .Converter.sourceAccessibility("Euro")) == "Source currency, Euro")
    #expect(String(localized: .Details.unitConversion("BTC", "USD")) == "1 BTC in USD")
    #expect(
      String(localized: .Details.chartAccessibility("One week", "EUR", "USD"))
        == "One week EUR to USD history")
    #expect(
      RateMessages.providerDescription(.init(provider: .fawaz, observation: .dailyRate))
        == "Fawaz · daily")
  }

  @Test func settingsAccessorsResolveFeatureBundle() {
    #expect(String(localized: .Converter.settings) == "Settings")
    #expect(String(localized: .Settings.settings) == "Settings")
    #expect(String(localized: .Settings.locationSettings) == "Location")
    var resource = LocalizedStringResource.Settings.quoteRetrieved("today")
    resource.locale = Locale(identifier: "uk_UA")
    #expect(String(localized: resource) == "Retrieved today")
    #expect(String(localized: .Settings.appearanceSystem) == "System")
    #expect(String(localized: .Settings.appearancePrimary) == "Default")
    #expect(String(localized: .Settings.acknowledgements) == "Acknowledgements")
  }

  @Test func onboardingAccessorsResolveFeatureBundleAndSubstitutions() {
    #expect(String(localized: .Onboarding.welcomeTitle) == "Currency, at a glance")
    #expect(String(localized: .Onboarding.baseTitle) == "Choose your base")
    #expect(String(localized: .Onboarding.updated("today")) == "Last updated today")
    var resource = LocalizedStringResource.Onboarding.homeScreenTitle
    resource.locale = Locale(identifier: "uk_UA")
    #expect(String(localized: resource) == "On your Home Screen")
  }

  @Test func ratesAndLoadingCopyPreserveTimestampMeaning() {
    #expect(String(localized: .Settings.ratesRetrieved) == "Rates retrieved")
    #expect(String(localized: .Settings.lastChecked) == "Last checked")
    #expect(
      String(localized: .Settings.quoteRetrieved("today"))
        == "Retrieved today")
    #expect(String(localized: .Details.loadingHistory) == "Loading history…")
    #expect(String(localized: HistoryRange.day.title) == "1D")
    #expect(String(localized: HistoryRange.yearToDate.title) == "YTD")
    #expect(String(localized: HistoryRange.day.accessibilityTitle) == "One day")
    #expect(String(localized: HistoryRange.yearToDate.accessibilityTitle) == "Year to date")
    #expect(
      String(localized: RateMessages.history(.intradayUnavailable)!)
        == "24-hour history is unavailable for fiat currencies. Choose 1W or a longer range.")
    #expect(
      RateMessages.providerDescription(
        .init(provider: .coinbase, observation: .hourlyClose, timeZone: .gmt),
        locale: Locale(identifier: "en_US")) == "Coinbase · hourly closes · GMT")
  }

  @Test func customProviderUsesLocalizedObservationTemplate() {
    let source = RateSource(
      provider: .custom("Example feed"), observation: .monthlyReference)
    #expect(
      RateMessages.providerDescription(source, locale: Locale(identifier: "en"))
        == "Example feed · monthly reference rates")
    #expect(
      RateMessages.providerDescription(.init(provider: .coinbase, observation: .exchangeRate))
        == "Coinbase · retrieved")
    #expect(
      String(localized: .Details.rateRetrieved("today"))
        == "Retrieved today · market timestamp unavailable")
    let daily = RateSource(provider: .coinbase, observation: .dailyClose, timeZone: .gmt)
    #expect(RateMessages.providerDescription(daily).hasPrefix("Coinbase · daily closes · "))
  }

  @Test func unsupportedLanguageFallsBackToEnglishCatalog() {
    var resource = LocalizedStringResource.Details.unitConversion("EUR", "USD")
    resource.locale = Locale(identifier: "uk_UA")
    #expect(String(localized: resource) == "1 EUR in USD")
  }
}
