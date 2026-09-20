import Foundation
import Testing

@testable import ExchangeRatesUI

@Suite struct CurrencyDisplayTests {
  @Test func formattingFollowsLocaleWithoutChangingEditablePrecision() {
    guard #available(iOS 26.0, *) else { return }
    let german = Locale(identifier: "de_DE")
    #expect(CurrencyDisplay.inputAmount("12.00", locale: german) == "12,00")
    #expect(CurrencyDisplay.inputAmount("12.", locale: german) == "12")
    #expect(CurrencyDisplay.inputAmount("0.", locale: german) == "0")
    #expect(
      CurrencyDisplay.format(Decimal(string: "1234.5"), code: "EUR", locale: german) == "1.234,5")
    #expect(CurrencyDisplay.format(nil, code: "EUR", locale: german) == "—")
  }

  @Test func flagDerivationHandlesRegionsSharedCurrenciesAndUnknownCodes() {
    guard #available(iOS 26.0, *) else { return }
    #expect(CurrencyDisplay.flag("UAH") == "🇺🇦")
    #expect(CurrencyDisplay.flag("XAF") == "🌍")
    #expect(CurrencyDisplay.flag("not-a-code") == "🪙")
  }

  @Test func keypadLabelsPreserveDecimalAndMultiZeroCommands() {
    guard #available(iOS 26.0, *) else { return }
    let german = Locale(identifier: "de_DE")
    #expect(CurrencyDisplay.keypadLabel(".", locale: german) == ",")
    #expect(CurrencyDisplay.keypadLabel("00", locale: german) == "00")
    #expect(CurrencyDisplay.keypadLabel("000", locale: german) == "000")
    #expect(CurrencyDisplay.keypadLabel("000", locale: Locale(identifier: "ar_EG")) == "٠٠٠")
  }

  @Test func editableAmountsGroupImmediatelyAndPreserveEveryFractionDigit() {
    guard #available(iOS 26.0, *) else { return }
    let english = Locale(identifier: "en_US")
    #expect(CurrencyDisplay.inputAmount("100000", locale: english) == "100,000")
    #expect(CurrencyDisplay.inputAmount("1234567.00", locale: english) == "1,234,567.00")
    #expect(CurrencyDisplay.inputAmount("1234.", locale: english) == "1,234")
    #expect(CurrencyDisplay.inputAmount("0.00001200", locale: english) == "0.00001200")
    #expect(CurrencyDisplay.inputAmount("", locale: english) == "0")
    #expect(
      CurrencyDisplay.inputAmount("1234567.50", locale: Locale(identifier: "de_DE"))
        == "1.234.567,50")
    #expect(
      CurrencyDisplay.inputAmount("1234567.50", locale: Locale(identifier: "en_IN"))
        == "12,34,567.50")
    #expect(
      CurrencyDisplay.inputAmount("1234.00", locale: Locale(identifier: "ar_EG")) == "١٬٢٣٤٫٠٠")
  }
}
