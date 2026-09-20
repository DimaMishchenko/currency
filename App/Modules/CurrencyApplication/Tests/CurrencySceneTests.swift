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
    // An underlying surface cannot take over the active location request.
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
