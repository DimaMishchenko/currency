import AppearancePreferences
import Conversion
import ExchangeRates
import Foundation
import Home
import LocalCurrency
import Settings
import Testing

@MainActor
struct AppCompositionTests {
  @Test func sharedContainerResolutionRequiresEntitlement() throws {
    #expect(throws: AppGroup.ResolutionError.missingEntitlement) {
      try AppGroup.resolve(using: { _ in nil })
    }
    let directory = URL(fileURLWithPath: "/isolated/shared")
    var identifier: String?
    #expect(
      try AppGroup.resolve(using: {
        identifier = $0; return directory
      }) == directory)
    #expect(identifier == "group.com.dimasike.currency.shared")
  }

  @Test func injectedCompositionSharesConfirmedInputRatesAndSettings() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer {
      try? FileManager.default.removeItem(at: directory)
      defaults.removePersistentDomain(forName: suite)
    }
    let composition = AppComposition(
      directory: directory,
      appearance: AppearancePreferences(defaults: defaults))
    let home = composition.home
    _ = try home.editInput {
      $0.setAmount("42"); $0.setDestinations(["USD"])
    }
    let other = ConversionStore(directory: directory)
    #expect(other.input().amount == "42")
    #expect(composition.onboarding.readInput() == other.input())
    let scene = composition.makeScene()
    let settings = composition.settings(scene: scene)
    #expect(settings.readState().codes == ["EUR", "USD"])
    settings.setTheme(.dark)
    #expect(composition.appearance.theme == .dark)
    let snapshot = RateSnapshot(
      quotes: [
        "EUR": ExchangeRate(1, published: "2026-09-26", source: .init(provider: .ecb)),
        "USD": ExchangeRate(2, published: "2026-09-26", source: .init(provider: .ecb))
      ], fetchedAt: .now)
    _ = try composition.onboarding.saveRates(snapshot, .now)
    #expect(home.readRates().quotes["USD"]?.value == 2)
    #expect(settings.readState().snapshot.quotes["USD"]?.value == 2)
    let controller = composition.makeLocationController()
    let flow = composition.location(controller: controller, scene: scene, id: UUID())
    #expect(flow.readSnapshot().phase == controller.phase)
    #expect(flow.readSnapshot().outcome == controller.outcome)
    try flow.addResolvedCurrency()
    #expect(other.input().usesLocalCurrency)
    controller.cancel()
  }
}
