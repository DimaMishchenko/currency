import ExchangeRates
import ExchangeRatesUI
import Foundation
import Testing

@Suite struct MetalAmountFormattingTests {
  @Test(
    arguments: [
      ("0", "0"),
      ("1.00000000", "1"),
      ("0.00120000", "0.0012"),
      ("0.123456789", "0.123457"),
      ("1.23456789", "1.23457"),
      ("12.3456789", "12.3457"),
      ("1234.56789", "1,234.57"),
      ("123456.789", "123,457"),
      ("1234567", "1,234,567"),
      ("1234567.89", "1,234,568"),
      ("123456789012345", "123,456,789,012,345"),
      ("0.000123456789", "0.000123457"),
      ("0.000000000123456789", "0.000000000123457"),
      ("0.00000000000000000000000000000000000001", "0.00000000000000000000000000000000000001"),
      ("0.9999999", "1"),
      ("0.0009999999", "0.001"),
      ("9.999999", "10"),
      ("999999.9", "1,000,000"),
      ("-0.000123456789", "-0.000123457"),
      ("-1234567", "-1,234,567")
    ])
  func metalResultsAndReferenceRatesShareCompactPrecision(
    input: String, expected: String
  ) throws {
    let value = try #require(Decimal(string: input))
    let locale = Locale(identifier: "en_US")
    for unit in MetalUnit.allCases {
      for code in ["XAU", "XAG", "XPT", "XPD"] {
        #expect(
          CurrencyDisplay.format(value, code: code, locale: locale, metalUnit: unit) == expected)
        #expect(
          CurrencyDisplay.referenceRate(
            value, from: "USD", to: code, locale: locale, metalUnit: unit) == expected)
      }
    }
  }

  @Test(arguments: [
    ("de_DE", "1.234,57", "0,000000000123457"),
    ("en_IN", "1,234.57", "0.000000000123457"),
    ("ar_EG", "١٬٢٣٤٫٥٧", "٠٫٠٠٠٠٠٠٠٠٠١٢٣٤٥٧")
  ])
  func metalFormattingRespectsLocale(identifier: String, amount: String, tinyRate: String) {
    let locale = Locale(identifier: identifier)
    #expect(
      CurrencyDisplay.format(Decimal(string: "1234.56789"), code: "XAU", locale: locale)
        == amount)
    #expect(
      CurrencyDisplay.referenceRate(
        Decimal(string: "0.000000000123456789"), from: "USD", to: "XAG", locale: locale)
        == tinyRate)
    #expect(
      CurrencyDisplay.format(
        Decimal(string: "1234567"), code: "XPT", locale: .init(identifier: "en_IN"))
        == "12,34,567")
  }

  @Test func missingMetalAmountsRemainExplicit() {
    for value: Decimal? in [nil, .nan] {
      #expect(CurrencyDisplay.format(value, code: "XAU") == "—")
      #expect(CurrencyDisplay.referenceRate(value, from: "USD", to: "XAU") == "—")
    }
  }

  @Test(arguments: [
    ("EUR", "1.23456789", "1.23"),
    ("KWD", "1.23456789", "1.235"),
    ("JPY", "1.23456789", "1"),
    ("BTC", "1.23456789", "1.23456789"),
    ("BTC", "0.000000001", "0")
  ])
  func fiatAndCryptoAmountsKeepExistingPrecision(code: String, input: String, expected: String) {
    #expect(
      CurrencyDisplay.format(
        Decimal(string: input), code: code, locale: .init(identifier: "en_US")) == expected)
  }

  @Test func metalInputAndSupportedPrecisionRemainUnchanged() {
    #expect(
      CurrencyDisplay.inputAmount("0.12345678900", locale: .init(identifier: "en_US"))
        == "0.12345678900")
    #expect(CurrencyDisplay.fractionDigits("XAU", metalUnit: .troyOunce) == 8)
    #expect(CurrencyDisplay.fractionDigits("XAU", metalUnit: .gram) == 8)
    #expect(CurrencyDisplay.fractionDigits("XAU", metalUnit: .kilogram) == 11)
    #expect(
      CurrencyDisplay.referenceRate(
        Decimal(string: "1.23456789"), from: "XAU", to: "USD", locale: .init(identifier: "en_US"))
        == "1.234568")
  }
}
