import Conversion
import CurrencyApplication
import ExchangeRates
import Foundation
import Testing

struct WatchCurrencyRouteTests {
  @Test func validRoutes() throws {
    #expect(
      WatchCurrencyRoute(url: try #require(URL(string: "currency-watch://convert"))) == .converter)
    #expect(
      WatchCurrencyRoute(
        url: try #require(URL(string: "currency-watch://convert?source=EUR&quote=USD&amount=100")))
        == .convert(source: "EUR", quote: "USD", amount: "100"))
    #expect(
      WatchCurrencyRoute(
        url: try #require(URL(string: "currency-watch://details?source=BTC&quote=USD")))
        == .details(source: "BTC", quote: "USD"))
  }
  @Test(arguments: ["12,5", " 0012.50 ", "12.5"])
  func routedAmountsAreCanonical(text: String) throws {
    var parts = URLComponents(string: "currency-watch://convert")!
    parts.queryItems = [
      .init(name: "source", value: "EUR"), .init(name: "quote", value: "USD"),
      .init(name: "amount", value: text)
    ]
    let url = try #require(parts.url)
    let route = try #require(WatchCurrencyRoute(url: url))
    #expect(route == .convert(source: "EUR", quote: "USD", amount: "12.5"))
    guard case .convert(_, _, let amount?, _) = route else { return }
    var input = ConverterState()
    input.setAmount(amount)
    #expect(input.decimal == Decimal(string: "12.5"))
  }

  @Test func convertedMetalMassIsAcceptedWithoutKeypadTruncation() throws {
    let mass = MetalUnit.gram.converted(1, to: .troyOunce)
    let text = ExactAmount.string(mass)
    #expect(text.count > 30)
    let url = try #require(
      URL(string: "currency-watch://convert?source=XAU&quote=EUR&amount=\(text)"))
    #expect(WatchCurrencyRoute(url: url) == .convert(source: "XAU", quote: "EUR", amount: text))
    var input = ConverterState()
    input.changeSource("XAU")
    input.setConvertedAmount(try #require(ExactAmount.parse(text)))
    #expect(input.decimal == mass)
  }

  @Test func measuredRoutePreservesMassAfterPreferenceChange() throws {
    let url = try #require(
      URL(string: "currency-watch://convert?source=XAU&quote=EUR&amount=1&metalUnit=gram"))
    guard case .convert(_, _, let amount?, let unit?) = WatchCurrencyRoute(url: url) else {
      Issue.record("Missing measured route"); return
    }
    var input = ConverterState()
    input.changeSource("XAU")
    input.setMetalUnit(.kilogram)
    input.setConvertedAmount(
      unit.converted(try #require(ExactAmount.parse(amount)), to: input.metalUnit))
    #expect(input.decimal == Decimal(string: "0.001"))
  }

  @Test(arguments: [
    "currency-watch://convert?source=XAU&quote=EUR&amount=1&metalUnit=invalid",
    "currency-watch://convert?source=EUR&quote=USD&amount=1&metalUnit=gram",
    "currency-watch://convert?source=EUR", "currency-watch://convert?source=EUR&quote=EUR",
    "currency-watch://convert?source=EUR&quote=USD&amount=-1",
    "currency-watch://convert?source=EUR&quote=USD&amount=",
    "currency-watch://convert?source=EUR&quote=USD&quote=GBP",
    "currency-watch://details?source=EUR&quote=USD&amount=10",
    "currency-watch://details?source=@local&quote=USD",
    "currency-watch://convert/path?source=EUR&quote=USD",
    "currency-watch://convert?source=EUR&quote=USD#extra",
    "currency-watch://convert?source=EUR&quote=USD&unknown=x",
    "https://convert?source=EUR&quote=USD"
  ]) func invalidRoutes(_ text: String) throws {
    #expect(WatchCurrencyRoute(url: try #require(URL(string: text))) == nil)
  }
}
