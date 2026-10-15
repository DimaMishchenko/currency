import ExchangeRates
import ExchangeRatesUI
import Foundation
import Testing

@Suite struct ReferenceRateFormattingTests {
  @Test(arguments: [
    ("BTC", "USD", "50000", "50,000"),
    ("ETH", "BTC", "0.002", "0.002"),
    ("USDC", "BTC", "0.00002", "0.00002"),
    ("VND", "BTC", "0.0000000008", "0.0000000008"),
    ("DOGE", "USD", "0.000001", "0.000001"),
    ("EUR", "USD", "1.1234567", "1.123457"),
    ("BTC", "KWD", "1.2346", "1.235"),
    ("USD", "EUR", "0", "0")
  ])
  func retainsMeaningfulReferenceValues(
    code: String, quote: String, value: String, expected: String
  ) throws {
    let decimal = try #require(Decimal(string: value))
    #expect(
      CurrencyDisplay.referenceRate(
        decimal, from: code, to: quote, locale: .init(identifier: "en_US"))
        == expected)
  }

  @Test func tinyRateRespectsLocaleAndMissingRateStaysExplicit() {
    let tiny = Decimal(string: "0.0000000008")
    #expect(
      CurrencyDisplay.referenceRate(
        tiny, from: "VND", to: "BTC", locale: .init(identifier: "de_DE"))
        == "0,0000000008")
    #expect(CurrencyDisplay.referenceRate(nil, from: "BTC", to: "EUR") == "—")
    #expect(CurrencyDisplay.referenceRate(.nan, from: "BTC", to: "EUR") == "—")
  }
}
