import AppearancePreferences
import CompanionSync
import Conversion
import ExchangeRates
import Foundation
import Home
import LocalCurrency
import Settings
import Testing
import Widgets

@MainActor
struct AppCompositionTests {
  @Test(arguments: SettingsAppIcon.allCases)
  func iconPresentationReconcilesPlatformChangesAndNewPresentations(icon: SettingsAppIcon) {
    var platformName = icon.platformIconName
    let current = AppIconPresentation(readName: { platformName })
    #expect(current.icon == icon)
    platformName = "AppIconGridBTC"
    current.reload()
    #expect(current.icon == .gridBitcoin)
    platformName = "AppIconWorldEUR"
    let reopened = AppIconPresentation(readName: { platformName })
    #expect(reopened.icon == .worldEuro)
    current.reload()
    #expect(current.icon == .worldEuro)
    platformName = nil
    current.reload()
    reopened.reload()
    #expect(current.icon == .world)
    #expect(reopened.icon == .world)
  }

  @Test func nativeIconCatalogHasElevenUniqueAlternatesAndOnePrimary() {
    let expected: [SettingsAppIcon: String] = [
      .worldEuro: "AppIconWorldEUR", .worldPound: "AppIconWorldGBP",
      .worldRupee: "AppIconWorldINR", .worldWon: "AppIconWorldKRW",
      .worldBitcoin: "AppIconWorldBTC", .grid: "AppIconGrid",
      .gridEuro: "AppIconGridEUR", .gridPound: "AppIconGridGBP",
      .gridRupee: "AppIconGridINR", .gridWon: "AppIconGridKRW",
      .gridBitcoin: "AppIconGridBTC"
    ]
    #expect(SettingsAppIcon.world.platformIconName == nil)
    #expect(SettingsAppIcon(platformIconName: nil) == .world)
    #expect(SettingsAppIcon(platformIconName: "unknown") == .world)
    #expect(Set(SettingsAppIcon.allCases.compactMap(\.platformIconName)).count == 11)
    for (icon, name) in expected {
      #expect(icon.platformIconName == name)
      #expect(SettingsAppIcon(platformIconName: name) == icon)
    }
  }

  @Test(arguments: [false, true])
  func unreadableInputPreservesPublishedFavorites(unreadable: Bool) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer {
      try? FileManager.default.removeItem(at: directory)
      defaults.removePersistentDomain(forName: suite)
    }
    let composition = AppComposition(
      directory: directory,
      appearance: AppearancePreferences(defaults: defaults), discoveryDefaults: defaults)
    try composition.conversion.updateInput { $0.setDestinations(["JPY"]) }
    composition.startCompanionSync()
    let metadata = CompanionSyncStateStore(directory: directory)
    let loaded = try metadata.load()
    let published = try #require(loaded)
    #expect(published.outgoing?.codes == ["EUR", "JPY"])
    #expect(published.outgoing?.revision == 1)
    let record = directory.appendingPathComponent("input.json")
    let confirmed = try Data(contentsOf: record)
    if unreadable {
      try FileManager.default.removeItem(at: record)
      try FileManager.default.createDirectory(at: record, withIntermediateDirectories: false)
    } else {
      try Data("invalid".utf8).write(to: record)
    }
    composition.changed()
    #expect(composition.companionIssue == .commitFailed)
    #expect(try metadata.load() == published)
    if unreadable {
      let attributes = try FileManager.default.attributesOfItem(atPath: record.path)
      #expect(attributes[.type] as? FileAttributeType == .typeDirectory)
      try FileManager.default.removeItem(at: record)
    } else {
      #expect(try Data(contentsOf: record) == Data("invalid".utf8))
    }
    try confirmed.write(to: record)
    _ = try composition.edit { $0.setDestinations(["CZK"]) }
    let recovered = try #require(metadata.load()?.outgoing)
    #expect(recovered.senderID == published.senderID)
    #expect(recovered.revision == 2)
    #expect(recovered.codes == ["EUR", "CZK"])
  }

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
      appearance: AppearancePreferences(defaults: defaults), discoveryDefaults: defaults)
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
        "EUR": ExchangeRate(1, published: "2026-09-26", source: .init(provider: .fawaz)),
        "USD": ExchangeRate(2, published: "2026-09-26", source: .init(provider: .fawaz))
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
    let beforeOpening = other.input()
    scene.open(.currency(CurrencyCode.jpy.rawValue))
    scene.receive(.completed, flowID: scene.onboardingID)
    #expect(scene.detail?.request.code == CurrencyCode.jpy.rawValue)
    #expect(other.input() == beforeOpening)
    controller.cancel()
  }
  @Test func settingsWidgetHapticsCommitIsSharedAndBroadcastWithoutChangingConverterInput()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer {
      try? FileManager.default.removeItem(at: directory)
      defaults.removePersistentDomain(forName: suite)
    }
    let composition = AppComposition(
      directory: directory,
      appearance: AppearancePreferences(defaults: defaults), discoveryDefaults: defaults)
    let settings = composition.settings(scene: composition.makeScene())
    let input = composition.conversion.input()
    #expect(!settings.readPreferences().widgetHapticsEnabled)
    let changes = composition.changes()
    var receivedChange = false
    let observation = Task {
      var updates = changes.makeAsyncIterator()
      receivedChange = await updates.next() != nil
    }
    try settings.setWidgetHapticsEnabled(true)
    for _ in 0..<1000 where !receivedChange { await Task.yield() }
    #expect(receivedChange)
    observation.cancel()
    await observation.value
    #expect(settings.readPreferences().widgetHapticsEnabled)
    #expect(WidgetStore(directory: directory).widgetHapticsEnabled())
    #expect(composition.conversion.input() == input)
    let reopened = AppComposition(
      directory: directory,
      appearance: AppearancePreferences(defaults: defaults), discoveryDefaults: defaults)
    let reopenedSettings = reopened.settings(scene: reopened.makeScene())
    #expect(reopenedSettings.readPreferences().widgetHapticsEnabled)
    try reopenedSettings.setWidgetHapticsEnabled(false)
    #expect(!settings.readPreferences().widgetHapticsEnabled)
    #expect(!WidgetStore(directory: directory).widgetHapticsEnabled())
  }

  @Test func failedWidgetHapticsCompositionWriteRetainsOffAndShowsTheCorrectFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer {
      try? FileManager.default.removeItem(at: directory)
      defaults.removePersistentDomain(forName: suite)
    }
    try FileManager.default.createDirectory(
      at: directory.appendingPathComponent("widget-haptics.json"),
      withIntermediateDirectories: true)
    let composition = AppComposition(
      directory: directory,
      appearance: AppearancePreferences(defaults: defaults), discoveryDefaults: defaults)
    let dependencies = composition.settings(scene: composition.makeScene())
    let model = SettingsModel(dependencies: dependencies)
    #expect(!model.preferences.widgetHapticsEnabled)
    model.setWidgetHapticsEnabled(true)
    #expect(!model.preferences.widgetHapticsEnabled)
    #expect(model.issue == .widgetHapticsSaveFailed)
    #expect(!WidgetStore(directory: directory).widgetHapticsEnabled())
    model.stop()
  }

}
