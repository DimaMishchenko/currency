import ExchangeRates
import ExchangeRatesUI
import Foundation
import Testing

@Suite struct ResourceTests {
  @Test func provenanceInterpolationUsesTheOwningCatalog() {
    guard #available(iOS 26.0, *) else { return }
    #expect(
      RateMessages.providerDescription(
        RateSource(provider: .coinbase, observation: .dailyClose, timeZone: .gmt),
        locale: Locale(identifier: "en_US")) == "Coinbase · daily closes · GMT")
    #expect(
      RateMessages.providerDescription(
        RateSource(provider: .custom("Example"), observation: .exchangeRate),
        locale: Locale(identifier: "en_US")) == "Example · retrieved")
  }
  @Test func systemPickerArtworkResolvesFromResourceBundle() {
    guard #available(iOS 26.0, *) else { return }
    #expect(CurrencyIcon.pickerImageData("BTC") != nil)
    #expect(CurrencyIcon.pickerImageData("XAU") != nil)
    #expect(CurrencyIcon.pickerImageData("EUR") != nil)
  }
}
