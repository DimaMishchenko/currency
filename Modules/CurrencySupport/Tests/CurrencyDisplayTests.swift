import Foundation
import Testing

@testable import CurrencySupport

@Suite struct CurrencyDisplayTests {
  @Test func formattingFollowsLocaleWithoutChangingEditablePrecision() {
    let german = Locale(identifier: "de_DE")
    #expect(CurrencyDisplay.inputAmount("12.00", locale: german) == "12,00")
    #expect(CurrencyDisplay.inputAmount("12.", locale: german) == "12,")
    #expect(
      CurrencyDisplay.format(Decimal(string: "1234.5"), code: "EUR", locale: german) == "1.234,5")
    #expect(CurrencyDisplay.format(nil, code: "EUR", locale: german) == "—")
  }
  @Test func flagDerivationHandlesRegionsSharedCurrenciesAndUnknownCodes() {
    #expect(CurrencyDisplay.flag("UAH") == "🇺🇦")
    #expect(CurrencyDisplay.flag("XAF") == "🌍")
    #expect(CurrencyDisplay.flag("not-a-code") == "🪙")
  }
}
