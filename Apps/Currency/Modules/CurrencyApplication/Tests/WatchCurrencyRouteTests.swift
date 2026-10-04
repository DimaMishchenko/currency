import Conversion
import CurrencyApplication
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
    guard case .convert(_, _, let amount?) = route else { return }
    var input = ConverterState()
    input.setAmount(amount)
    #expect(input.decimal == Decimal(string: "12.5"))
  }

  @Test(arguments: [
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
