import ExchangeRates
import Foundation
import Testing

struct CurrencyCatalogTests {
  @Test func curatedBrowsingSeparatesPopularAndAlphabeticalCurrencies() {
    #expect(CurrencyCatalog.popularFiat == ["USD", "EUR", "JPY", "GBP", "CHF", "CAD", "AUD", "CNY"])
    #expect(!CurrencyCatalog.popularFiat.contains("CZK"))
    #expect(CurrencyCatalog.otherFiat.contains("CZK"))
    #expect(CurrencyCatalog.otherFiat == CurrencyCatalog.otherFiat.sorted())
    #expect(CurrencyCatalog.otherCrypto == CurrencyCatalog.otherCrypto.sorted())
    let fiat = CurrencyCatalog.popularFiat + CurrencyCatalog.otherFiat
    let crypto = CurrencyCatalog.popularCrypto + CurrencyCatalog.otherCrypto
    #expect(Set(fiat).count == fiat.count)
    #expect(Set(crypto).count == crypto.count)
    #expect(Set(crypto) == CurrencyCatalog.crypto)
    #expect(Set(fiat + crypto).union(CurrencyCatalog.metals) == Set(CurrencyCatalog.codes))
  }

  @Test func searchRanksCodeMatchesBeforeLocalizedNameMatchesAndRespectsFiltering() {
    let names = ["USD": "US Dollar", "USDC": "USD Coin", "AUD": "Australian Dollar"]
    #expect(CurrencyCatalog.search(" usd ", name: { names[$0] ?? $0 }) == ["USD", "USDC", "USDT"])
    #expect(CurrencyCatalog.search("dollar", name: { names[$0] ?? $0 }) == ["AUD", "USD"])
    #expect(
      CurrencyCatalog.search("usd", allowedCodes: ["USDC"], name: { names[$0] ?? $0 }) == ["USDC"])
    #expect(CurrencyCatalog.search("   ", name: { $0 }).isEmpty)
  }

  @Test func searchNormalizesLocalizedNamesAndKeepsDeterministicTies() {
    let names = ["CZK": "Česká koruna", "SEK": "Švédská koruna"]
    #expect(
      CurrencyCatalog.search(
        "ceska", locale: Locale(identifier: "cs_CZ"), name: { names[$0] ?? $0 }) == ["CZK"])
    #expect(CurrencyCatalog.search("koruna", name: { names[$0] ?? $0 }) == ["CZK", "SEK"])
  }
}
