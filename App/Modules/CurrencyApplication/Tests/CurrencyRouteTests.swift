import Conversion
import CurrencyApplication
import Foundation
import Home
import LocalCurrency
import Onboarding
import Testing

@MainActor @Suite struct CurrencyRouteTests {
  @Test(arguments: ["EUR", "USD", "@local"])
  func selectedContentRouteRoundTrip(_ id: String) throws {
    let route = CurrencyRoute.currency(id)
    #expect(CurrencyRoute(url: try #require(route.url)) == route)
  }
  @Test(arguments: [
    "currency://currency?id=USD", "currency://currency?v=2&id=USD",
    "currency://currency?v=1&id=WRONG", "currency://currency?v=1&id=USD&id=EUR",
    "currency://conversion?v=1&request=garbage", "https://currency?v=1&id=USD",
    "currency://currency/path?v=1&id=USD"
  ])
  func invalidURLsFailClosed(_ text: String) throws {
    #expect(CurrencyRoute(url: try #require(URL(string: text))) == nil)
  }
  @Test func latestRouteWaitsForItsSceneOnboardingAndOpensWithoutZoom() throws {
    let first = CurrencyScene(
      completed: false, replay: {},
      openCurrency: { id in
        HomeDetailsRequest(selectionID: id, code: id, reference: "EUR", snapshot: .init())
      })
    let second = CurrencyScene(completed: true, replay: {})
    first.open(try #require(CurrencyRoute.currency("USD").url))
    first.open(try #require(CurrencyRoute.currency("GBP").url))
    #expect(first.detail == nil && second.detail == nil)
    first.receive(.completed, flowID: UUID())
    #expect(first.detail == nil)
    first.receive(OnboardingOutput.completed, flowID: first.onboardingID)
    #expect(first.detail?.request.code == "GBP" && first.detail?.usesZoom == false)
    #expect(second.detail == nil)
  }
  @Test func removedSelectionDoesNotOpenOrChangeExistingNavigation() throws {
    let scene = CurrencyScene(completed: true, replay: {}, openCurrency: { _ in nil })
    scene.path = [.settings(UUID())]
    let original = scene.path
    scene.open(try #require(CurrencyRoute.currency("USD").url))
    #expect(scene.path == original && scene.detail == nil)
  }
}
