import Conversion
import ExchangeRates
import Foundation
import Home
import Onboarding
import Testing

@testable import CurrencyApplication

@MainActor @Suite struct CurrencySceneTests {
  private var details: HomeDetailsRequest {
    HomeDetailsRequest(selectionID: "USD", code: "USD", reference: "EUR", snapshot: RateSnapshot())
  }

  @Test func scenesKeepIndependentNavigationAndFlowIdentities() {
    let first = CurrencyScene(completed: true, replay: {})
    let second = CurrencyScene(completed: true, replay: {})
    first.receive(HomeOutput.detailsRequested(details))
    first.receive(HomeOutput.settingsRequested)
    #expect(first.id != second.id)
    #expect(first.homeID != second.homeID)
    #expect(first.onboardingID != second.onboardingID)
    #expect(first.path.count == 1)
    #expect(first.detail?.request.selectionID == "USD")
    #expect(first.sheet == nil)
    #expect(second.path.isEmpty)
    #expect(second.sheet == nil)
    #expect(second.detail == nil)
  }

  @Test func failedReplayPreservesCurrentRoutesAndIdentities() {
    var attempts = 0
    let scene = CurrencyScene(completed: true) {
      attempts += 1
      throw CocoaError(.fileWriteNoPermission)
    }
    scene.receive(HomeOutput.detailsRequested(details))
    scene.receive(HomeOutput.settingsRequested)
    scene.receive(HomeOutput.widgetsRequested)
    scene.requestLocation(addsToApp: true)
    let home = scene.homeID
    let onboarding = scene.onboardingID
    let sheet = scene.sheet?.id
    let detail = scene.detail?.id
    let location = scene.location?.id
    #expect(throws: CocoaError.self) { try scene.restartOnboarding() }
    #expect(attempts == 1)
    #expect(scene.homeID == home)
    #expect(scene.onboardingID == onboarding)
    #expect(scene.sheet?.id == sheet)
    #expect(scene.detail?.id == detail)
    #expect(scene.location?.id == location)
    #expect(scene.path.count == 1)
    #expect(!scene.showsOnboarding)
    #expect(scene.preloadsHome)
  }

  @Test func successfulReplayReplacesFlowsOnlyAfterPersistence() throws {
    var committed = false
    let scene = CurrencyScene(completed: true) { committed = true }
    let home = scene.homeID
    let onboarding = scene.onboardingID
    scene.receive(HomeOutput.detailsRequested(details))
    scene.receive(HomeOutput.settingsRequested)
    scene.requestLocation(addsToApp: true)
    try scene.restartOnboarding()
    #expect(committed)
    #expect(scene.homeID != home)
    #expect(scene.onboardingID != onboarding)
    #expect(scene.path.isEmpty)
    #expect(scene.detail == nil)
    #expect(scene.sheet == nil)
    #expect(scene.location == nil)
    #expect(scene.showsOnboarding)
    #expect(!scene.preloadsHome)
  }

  @Test func finalePreloadsSameHomeBeforeCommittedCompletion() {
    let scene = CurrencyScene(completed: false, replay: {})
    let home = scene.homeID
    #expect(scene.showsOnboarding)
    #expect(!scene.preloadsHome)
    scene.receive(OnboardingOutput.finalePresented, flowID: scene.onboardingID)
    #expect(scene.preloadsHome)
    #expect(scene.showsOnboarding)
    #expect(scene.homeID == home)
    scene.receive(OnboardingOutput.completed, flowID: scene.onboardingID)
    #expect(!scene.showsOnboarding)
    #expect(scene.homeID == home)
  }

  @Test func supersededOnboardingOutputCannotCompleteNewReplay() throws {
    let scene = CurrencyScene(completed: false, replay: {})
    let previous = scene.onboardingID
    try scene.restartOnboarding()
    scene.receive(OnboardingOutput.finalePresented, flowID: previous)
    scene.receive(OnboardingOutput.completed, flowID: previous)
    #expect(scene.showsOnboarding)
    #expect(!scene.preloadsHome)
  }

  @Test func locationDismissalIsCorrelatedAndRepeatedRequestKeepsActiveFlow() throws {
    let scene = CurrencyScene(completed: true, replay: {})
    scene.requestLocation(addsToApp: true)
    let first = try #require(scene.location)
    scene.requestLocation(addsToApp: false)
    #expect(scene.location?.id == first.id)
    #expect(scene.location?.addsToApp == true)
    scene.finishLocation(id: UUID())
    #expect(scene.location?.id == first.id)
    scene.finishLocation(id: first.id)
    #expect(scene.location == nil)
    scene.requestLocation(addsToApp: false)
    let second = try #require(scene.location)
    scene.finishLocation(id: first.id)
    #expect(scene.location?.id == second.id)
  }

  @Test func onlySupportedDeepLinkOpensLocationWithoutAddingToApp() throws {
    let scene = CurrencyScene(completed: true, replay: {})
    scene.open(try #require(URL(string: "https://local-currency")))
    scene.open(try #require(URL(string: "currency://unrecognized")))
    #expect(scene.location == nil)
    scene.open(try #require(URL(string: "currency://local-currency")))
    #expect(scene.location?.addsToApp == false)
    #expect(scene.path.isEmpty)
  }

  @Test func widgetLocationReturnsToItsRequestingSurface() throws {
    let scene = CurrencyScene(completed: true, replay: {})
    scene.receive(HomeOutput.widgetsRequested)
    let widgetFlow = try #require(scene.sheet).id
    let collection = UUID()
    let tutorial = UUID()
    scene.requestLocation(addsToApp: false, presenterID: tutorial)
    let location = try #require(scene.locationPresented(by: tutorial))
    #expect(scene.locationPresented(by: collection) == nil)
    #expect(scene.locationPresented(by: nil) == nil)
    scene.requestLocation(addsToApp: false, presenterID: collection)
    #expect(scene.locationPresented(by: tutorial)?.id == location.id)
    scene.finishLocation(id: location.id)
    #expect(scene.locationPresented(by: tutorial) == nil)
    #expect(scene.sheet?.id == widgetFlow)
    scene.open(try #require(URL(string: "currency://local-currency")))
    #expect(scene.locationPresented(by: nil) != nil)
    #expect(scene.locationPresented(by: tutorial) == nil)
  }

  @Test func replayClearsLocationOwnedByAnOnboardingTutorial() throws {
    let scene = CurrencyScene(completed: false, replay: {})
    let presenter = UUID()
    scene.requestLocation(addsToApp: false, presenterID: presenter)
    let old = try #require(scene.locationPresented(by: presenter))
    try scene.restartOnboarding()
    #expect(scene.locationPresented(by: presenter) == nil)
    scene.requestLocation(addsToApp: false, presenterID: UUID())
    let new = try #require(scene.location)
    scene.finishLocation(id: old.id)
    #expect(scene.location?.id == new.id)
  }

}

@MainActor @Suite struct WidgetQuoteHandoffTests {
  @Test func renderedSnapshotIsSceneLocalAndCorrelatedUntilRefresh() throws {
    let id = UUID()
    let rendered = RateSnapshot(quotes: [
      "USD": ExchangeRate(
        1.1, published: "2026-10-16",
        source: .init(provider: .frankfurter))
    ])
    let first = CurrencyScene(
      completed: true, replay: {},
      readWidgetContext: { $0 == id ? CurrencyScene.WidgetContext(snapshot: rendered) : nil })
    let second = CurrencyScene(completed: true, replay: {})
    let previousFlow = first.homeID
    let route = CurrencyRoute.widget(id)
    #expect(CurrencyRoute(url: try #require(route.url)) == route)
    first.open(route)
    #expect(first.homeID != previousFlow)
    #expect(first.widgetSnapshot?.quotes["USD"]?.value == 1.1)
    #expect(second.widgetSnapshot == nil)
    first.finishWidgetHandoff(id: UUID())
    #expect(first.widgetSnapshot != nil)
    first.finishWidgetHandoff(id: id)
    #expect(first.widgetSnapshot == nil)
    #expect(first.widgetContextID == nil)
    first.open(.widget(UUID()))
    #expect(first.widgetSnapshot == nil)
    #expect(CurrencyRoute(url: try #require(URL(string: "currency://convert"))) == .converter)
    #expect(
      CurrencyRoute(url: try #require(URL(string: "currency://widget?v=2&context=\(id)"))) == nil)
    #expect(
      CurrencyRoute(url: try #require(URL(string: "currency://widget?v=1&context=bad"))) == nil)
  }
}

@MainActor @Suite struct WidgetPairHandoffTests {
  @Test func customHistoryPairOpensItsQuoteWithoutChangingSavedInput() {
    let id = UUID()
    let snapshot = RateSnapshot(quotes: [
      "BTC": ExchangeRate(
        0.00001, published: "2026-10-16",
        source: .init(provider: .coinMetrics))
    ])
    let saved = ConverterState()
    let scene = CurrencyScene(
      completed: true, replay: {},
      readWidgetContext: { _ in
        CurrencyScene.WidgetContext(snapshot: snapshot, base: "BTC", quote: "USD")
      }, readInput: { saved })
    scene.open(.widget(id))
    #expect(scene.detail?.request.code == "BTC")
    #expect(scene.detail?.request.reference == "USD")
    #expect(scene.detail?.request.snapshot.quotes["BTC"]?.value == 0.00001)
    #expect(saved.source == ConverterState().source)
    let newer = RateSnapshot(quotes: [
      "BTC": ExchangeRate(
        0.00002, published: "2026-10-16",
        source: .init(provider: .coinMetrics))
    ])
    scene.finishWidgetHandoff(id: id, snapshot: newer)
    #expect(scene.detail?.request.snapshot.quotes["BTC"]?.value == 0.00002)
    #expect(scene.widgetSnapshot == nil)
  }

  @Test func visibleHomePairStaysInTheConverter() {
    let id = UUID()
    var saved = ConverterState()
    saved.changeSource("BTC")
    saved.setDestinations(["USD"])
    let input = saved
    let scene = CurrencyScene(
      completed: true, replay: {},
      readWidgetContext: { _ in
        CurrencyScene.WidgetContext(snapshot: RateSnapshot(), base: "BTC", quote: "USD")
      }, readInput: { input })
    scene.open(.widget(id))
    #expect(scene.detail == nil)
    #expect(scene.widgetSnapshot != nil)
  }
}

@MainActor @Suite struct WidgetNavigationSupersessionTests {
  @Test(arguments: [CurrencyRoute.converter, .currency("EUR")])
  func externalNavigationInvalidatesThePreviousHandoff(route: CurrencyRoute) {
    let widgetID = UUID()
    let snapshot = RateSnapshot()
    let scene = CurrencyScene(
      completed: true, replay: {},
      readWidgetContext: { _ in
        CurrencyScene.WidgetContext(snapshot: snapshot, base: "BTC", quote: "USD")
      },
      openCurrency: { code in
        HomeDetailsRequest(selectionID: code, code: code, reference: "USD", snapshot: snapshot)
      })
    scene.open(.widget(widgetID))
    let widgetDetails = scene.detail?.id
    #expect(widgetDetails != nil)
    scene.open(route)
    let externalDetails = scene.detail?.id
    #expect(scene.widgetContextID == nil)
    #expect(scene.widgetSnapshot == nil)
    scene.finishWidgetHandoff(id: widgetID, snapshot: RateSnapshot())
    #expect(scene.detail?.id == externalDetails)
    #expect(scene.detail?.id != widgetDetails)
    if case .currency = route { #expect(scene.detail?.request.code == "EUR") }
  }

  @Test func handoffRefreshPreservesDetailsFlowIdentity() {
    let widgetID = UUID()
    let scene = CurrencyScene(
      completed: true, replay: {},
      readWidgetContext: { _ in
        CurrencyScene.WidgetContext(snapshot: RateSnapshot(), base: "BTC", quote: "USD")
      })
    scene.open(.widget(widgetID))
    let flowID = scene.detail?.id
    scene.releaseWidgetSnapshot(id: widgetID, snapshot: RateSnapshot())
    #expect(scene.widgetSnapshot == nil)
    #expect(scene.widgetContextID == widgetID)
    #expect(scene.detail?.id == flowID)
    scene.finishWidgetHandoff(id: widgetID, snapshot: RateSnapshot())
    #expect(scene.detail?.id == flowID)
  }
}
