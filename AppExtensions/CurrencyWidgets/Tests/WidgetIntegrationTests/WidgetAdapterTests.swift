import Conversion
import ExchangeRates
import Foundation
import LocalCurrency
import Synchronization
import Testing
import UIKit
import WidgetKit
import Widgets
import WidgetsUI

@Suite struct WidgetAdapterTests {
  @Test(arguments: WidgetCommand.Key.allCases)
  func enabledKeypadFeedbackFollowsSuccessfulActionExactlyOnce(_ key: WidgetCommand.Key) throws {
    try expectEnabledFeedback(command: key.rawValue)
  }

  @Test(arguments: ["select:USD", "preset:10"])
  func enabledSelectionAndPresetFeedbackFollowsSuccessfulActionExactlyOnce(_ command: String) throws
  {
    try expectEnabledFeedback(command: command)
  }

  @Test func synchronizedActionRequestsOneHapticAfterReload() throws {
    try expectEnabledFeedback(command: "7", reload: true)
  }

  private func expectEnabledFeedback(command: String, reload: Bool = false) throws {
    let events = Mutex<[String]>([])
    let dependencies = WidgetActionDependencies(
      rates: { RateSnapshot() },
      apply: { _, _, _ in
        events.withLock { $0.append("commit") }
        return reload
      },
      reloadSynchronizedWidgets: { events.withLock { $0.append("reload") } },
      hapticsEnabled: {
        events.withLock { $0.append("preference") }
        return true
      },
      playHaptic: { events.withLock { $0.append("feedback") } })
    let spec = WidgetSpec(kind: "CurrencyCash", codes: ["EUR", "USD"], status: .notDetermined)
    try WidgetAction(WidgetCommand(command, spec: spec)).execute(using: dependencies)
    #expect(
      events.withLock { $0 }
        == (reload
          ? ["commit", "reload", "preference", "feedback"] : ["commit", "preference", "feedback"]))
  }

  @Test func widgetActionReadsLatestHapticsPreferenceWithoutRecreatingDependencies() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = WidgetStore(directory: directory)
    let widget = WidgetStore(directory: directory)
    let requests = Mutex(0)
    let dependencies = WidgetActionDependencies(
      rates: { RateSnapshot() }, apply: { _, _, _ in false },
      reloadSynchronizedWidgets: {},
      hapticsEnabled: { widget.widgetHapticsEnabled() },
      playHaptic: { requests.withLock { $0 += 1 } })
    let spec = WidgetSpec(kind: "CurrencyCash", codes: ["EUR", "USD"], status: .notDetermined)
    let action = WidgetAction(WidgetCommand("AC", spec: spec))
    try action.execute(using: dependencies)
    #expect(requests.withLock { $0 } == 0)
    try app.setWidgetHapticsEnabled(true)
    try action.execute(using: dependencies)
    #expect(requests.withLock { $0 } == 1)
    try app.setWidgetHapticsEnabled(false)
    try action.execute(using: dependencies)
    #expect(requests.withLock { $0 } == 1)
  }

  @Test func failedOrUnknownWidgetActionNeverRequestsHaptics() throws {
    let failure = WidgetActionDependencies(
      rates: { RateSnapshot() },
      apply: { _, _, _ in throw CocoaError(.fileWriteNoPermission) },
      reloadSynchronizedWidgets: { Issue.record("Failed commit must not reload") },
      hapticsEnabled: {
        Issue.record("Failed commit must not read the feedback preference")
        return true
      },
      playHaptic: { Issue.record("Failed commit must not request feedback") })
    let spec = WidgetSpec(kind: "CurrencyCash", codes: ["EUR", "USD"], status: .notDetermined)
    #expect(throws: CocoaError.self) {
      try WidgetAction(WidgetCommand("7", spec: spec)).execute(using: failure)
    }
    let unknown = WidgetActionDependencies(
      rates: { RateSnapshot() }, apply: { _, _, _ in false },
      reloadSynchronizedWidgets: { Issue.record("Unknown action must not reload") },
      hapticsEnabled: {
        Issue.record("Unknown action must not read the feedback preference")
        return true
      },
      playHaptic: { Issue.record("Unknown action must not request feedback") })
    try WidgetAction(WidgetCommand("unknown", spec: spec)).execute(using: unknown)
  }

  private var rates: RateSnapshot {
    RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .ecb)),
      "USD": ExchangeRate(2, published: "2026-09-19", source: .init(provider: .ecb)),
      "CZK": ExchangeRate(25, published: "2026-09-19", source: .init(provider: .ecb))
    ])
  }

  @Test func nativeConfigurationPreservesCustomIdentityAndExplicitLocationStatus() {
    let settings = MultiSettings()
    settings.list = .selected
    settings.currencies = [WidgetCurrency("USD"), WidgetCurrency("@local")]
    settings.instance = CalculatorInstance(id: "12345678-1234-1234-1234-123456789012")
    let observation = WidgetLocation(country: "CZ", currency: "CZK")
    let spec = settings.specification(
      kind: "CurrencyConverter", input: ConverterState(), location: observation, status: .denied)
    #expect(spec.canonicalCodes == ["USD", "@local"])
    #expect(spec.codes == ["USD", "@local"])
    #expect(spec.localCode == nil)
    #expect(!spec.synchronized)
    #expect(spec.key == "CurrencyConverter|instance|12345678-1234-1234-1234-123456789012|custom")
  }

  @Test func boardAndCalculatorConsumeSameSuppliedAppSnapshot() {
    var app = ConverterState()
    app.setDestinations(["USD", "CZK"])
    app.setAmount("42")
    let board = BoardSettings()
    board.list = .synchronized
    let boardSpec = board.specification(
      kind: "CurrencyBoard", input: app, location: nil, status: .notDetermined)
    let calculator = MultiSettings()
    calculator.list = .synchronized
    let calculatorSpec = calculator.specification(
      kind: "CurrencyConverter", input: app, location: nil, status: .notDetermined)
    #expect(boardSpec.codes == ["EUR", "USD", "CZK"])
    #expect(boardSpec.amount == "42")
    #expect(calculatorSpec.canonicalCodes == ["EUR", "USD", "CZK"])
    app.setUsesLocalCurrency(true)
    let localSpec = calculator.specification(
      kind: "CurrencyConverter", input: app, location: nil, status: .notDetermined)
    #expect(localSpec.canonicalCodes == ["EUR", "USD", "CZK", "@local"])
    #expect(calculatorSpec.synchronized)
  }

  @Test func calculatorAndBoardTimelineReadSavedUnitWhileReferenceWidgetsKeepExplicitUnits() {
    var input = ConverterState()
    input.setMetalUnit(.kilogram)
    let app = input
    let rates = rates
    let dependencies = WidgetTimelineDependencies(
      input: { app }, rates: { rates }, localSnapshot: { (nil, .notDetermined) },
      widgetInput: { _, codes, amount in WidgetInput(codes: codes, amount: amount) },
      refreshRates: { _ in .init(snapshot: rates, warning: nil) },
      refreshLocalCurrency: {}, now: { .now })
    let calculator = SuiteTimeline<MultiSettings>(
      kind: "CurrencyConverter", dependencies: dependencies
    )
    .entry(MultiSettings())
    let board = SuiteTimeline<BoardSettings>(kind: "CurrencyBoard", dependencies: dependencies)
      .entry(BoardSettings())
    let reference = SuiteTimeline<CashSettings>(kind: "CurrencyCash", dependencies: dependencies)
      .entry(CashSettings())
    #expect(calculator.input.metalUnit == .kilogram)
    #expect(board.input.metalUnit == .kilogram)
    #expect(reference.input.metalUnit == .troyOunce)
    #expect(WidgetPresets.convert(1000, from: "XAU", to: "XAU", snapshot: rates) == 1000)
  }

  @Test func recentlyEditedTimelineAvoidsRefreshAndPreservesCurrentInput() async {
    let calls = Mutex(0)
    var input = WidgetInput(codes: ["EUR", "USD"])
    input.press("7")
    let current = input
    let now = Date.now
    let rates = rates
    let dependencies = WidgetTimelineDependencies(
      input: { ConverterState() }, rates: { rates }, localSnapshot: { (nil, .notDetermined) },
      widgetInput: { _, _, _ in current },
      refreshRates: { _ in
        calls.withLock { $0 += 1 }
        return RefreshResult(snapshot: rates, warning: nil)
      },
      refreshLocalCurrency: { calls.withLock { $0 += 1 } }, now: { now })
    let settings = MultiSettings()
    settings.list = .selected
    settings.currencies = [WidgetCurrency("EUR"), WidgetCurrency("USD")]
    let timeline = await SuiteTimeline<MultiSettings>(
      kind: "CurrencyConverter", dependencies: dependencies
    )
    .loadTimeline(settings)
    #expect(calls.withLock { $0 } == 0)
    #expect(timeline.entries.first?.input.amount == "7")
    #expect(timeline.policy == .after(now.addingTimeInterval(1800)))
  }

  @Test func failedRefreshKeepsCachedQuotesAndSchedulesRetry() async {
    let now = Date.now
    let rates = rates
    let dependencies = WidgetTimelineDependencies(
      input: { ConverterState() }, rates: { rates }, localSnapshot: { (nil, .notDetermined) },
      widgetInput: { _, codes, amount in WidgetInput(codes: codes, amount: amount) },
      refreshRates: { _ in throw CocoaError(.fileReadUnknown) },
      refreshLocalCurrency: {}, now: { now })
    let timeline = await SuiteTimeline<AnchorSettings>(
      kind: "CurrencyPocketRate", dependencies: dependencies
    )
    .loadTimeline(AnchorSettings())
    #expect(timeline.entries.first?.snapshot.quotes["USD"]?.value == 2)
    #expect(timeline.policy == .after(now.addingTimeInterval(300)))
  }

  @Test func timelineIncludesExplicitLocalExpiry() {
    let now = Date.now
    let location = WidgetLocation(country: "CZ", currency: "CZK", updatedAt: now)
    let rates = rates
    let localReads = Mutex(0)
    let dependencies = WidgetTimelineDependencies(
      input: { ConverterState() }, rates: { rates },
      localSnapshot: {
        localReads.withLock { $0 += 1 }
        return (location, .available)
      },
      widgetInput: { _, codes, amount in WidgetInput(codes: codes, amount: amount) },
      refreshRates: { _ in RefreshResult(snapshot: rates, warning: nil) },
      refreshLocalCurrency: {}, now: { now })
    let settings = AnchorSettings()
    settings.comparison = WidgetCurrency("@local")
    let provider = SuiteTimeline<AnchorSettings>(
      kind: "CurrencyPocketRate", dependencies: dependencies)
    let timeline = provider.timeline(starting: provider.entry(settings))
    #expect(localReads.withLock { $0 } == 1)
    #expect(timeline.entries.count == 2)
    #expect(timeline.entries[0].spec.localIsStale == false)
    #expect(timeline.entries[1].date == now.addingTimeInterval(86400))
    #expect(timeline.entries[1].spec.localIsStale)
  }

  @Test func intentUsesPersistedKeyAndReloadsOnlyAfterSuccessfulCommit() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    let conversion = ConversionStore(directory: directory)
    let reloads = Mutex(0)
    let reads = Mutex(0)
    let rates = rates
    let dependencies = WidgetActionDependencies(
      rates: {
        reads.withLock { $0 += 1 }; return rates
      },
      apply: { action, key, snapshot in
        try store.apply(action, key: key, snapshot: snapshot)
      },
      reloadSynchronizedWidgets: { reloads.withLock { $0 += 1 } },
      hapticsEnabled: { false }, playHaptic: { Issue.record("Feedback is disabled") })
    var spec = WidgetSpec(
      kind: "CurrencyConverter", codes: ["EUR", "USD"], instanceID: "stable", status: .notDetermined
    )
    spec.synchronized = true
    let action = WidgetAction(WidgetCommand("7", spec: spec))
    try action.execute(using: dependencies)
    #expect(store.widgetInput(key: spec.key, codes: spec.codes).amount == "7")
    #expect(conversion.input().amount == "7")
    #expect(reads.withLock { $0 } == 1)
    #expect(reloads.withLock { $0 } == 1)
    let failure = WidgetActionDependencies(
      rates: { rates }, apply: { _, _, _ in throw CocoaError(.fileWriteNoPermission) },
      reloadSynchronizedWidgets: { reloads.withLock { $0 += 1 } },
      hapticsEnabled: { false }, playHaptic: { Issue.record("Feedback is disabled") })
    #expect(throws: CocoaError.self) { try action.execute(using: failure) }
    #expect(reloads.withLock { $0 } == 1)
  }

  @Test func customKeypadIntentDoesNotReadRatesOrReloadOtherWidgets() throws {
    let reads = Mutex(0)
    let seen = Mutex<String?>(nil)
    let dependencies = WidgetActionDependencies(
      rates: {
        reads.withLock { $0 += 1 }; return RateSnapshot()
      },
      apply: { action, key, snapshot in
        #expect(snapshot == nil)
        #expect(action.command == "7")
        seen.withLock { $0 = key }
        return false
      },
      reloadSynchronizedWidgets: { Issue.record("Custom input must not reload unrelated widgets") },
      hapticsEnabled: { false }, playHaptic: { Issue.record("Feedback is disabled") })
    let spec = WidgetSpec(kind: "CurrencyCash", codes: ["EUR", "USD"], status: .notDetermined)
    try WidgetAction(WidgetCommand("7", spec: spec)).execute(using: dependencies)
    #expect(reads.withLock { $0 } == 0)
    #expect(seen.withLock { $0 } == spec.key)
  }

  @Test func customBoardPickerPreservesLocalThroughSelectionSearchAndConversion() async throws {
    let choices = try await BoardCurrencyOptionsProvider(readInput: { ConverterState() }).results()
    #expect(choices.items.contains { $0.id == WidgetSelection.localID })
    let localName = String(
      localized: "localCurrencyChoice", defaultValue: "Local currency", table: "Widgets")
    let matches = try await ComparisonCurrencyQuery(readInput: { ConverterState() })
      .entities(matching: localName)
    #expect(matches.items.contains { $0.id == WidgetSelection.localID })
    let restored = try await WidgetCurrencyIdentityQuery()
      .entities(
        for: ["USD", WidgetSelection.localID])
    #expect(restored.map(\.id) == ["USD", WidgetSelection.localID])
    let settings = BoardSettings()
    settings.list = .selected
    settings.currencies = restored
    let spec = settings.specification(
      kind: "CurrencyBoard", input: ConverterState(),
      location: WidgetLocation(country: "CZ", currency: "CZK"), status: .available)
    #expect(spec.canonicalCodes == ["EUR", "USD", WidgetSelection.localID])
    #expect(spec.localCode == "CZK")
  }

  @Test func customCurrencyPickersNormalizeSavedSelections() async throws {
    let identifiers = ["USD", "invalid", "@local", "USD", "BTC", "@local", "EUR"]
    let restored = try await WidgetCurrencyIdentityQuery().entities(for: identifiers)
    #expect(restored.map(\.id) == ["USD", "@local", "BTC", "EUR"])
  }

  @Test func customCurrencyProvidersKeepTheFullCatalogInAppOrder() async throws {
    var input = ConverterState()
    input.changeSource("CHF")
    input.setDestinations(["BTC", "EUR", "USD"])
    let saved = input
    let calculator = MultiCurrencyOptionsProvider(readInput: { saved })
    let board = BoardCurrencyOptionsProvider(readInput: { saved })
    for ids in [
      try await calculator.results().items.map(\.id),
      try await board.results().items.map(\.id)
    ] {
      #expect(Array(ids.prefix(5)) == ["CHF", "BTC", "EUR", "USD", "@local"])
      #expect(ids.count == CurrencyCatalog.codes.count + 1)
      #expect(Set(ids) == Set(CurrencyCatalog.codes + [WidgetSelection.localID]))
    }
  }

  @Test func customCurrencyProvidersSeedOnlyTheCustomList() {
    var input = ConverterState()
    input.changeSource("CHF")
    input.setDestinations(["BTC", "EUR", "USD"])
    let options = CurrencyListOptions(input: input)
    #expect(
      options.defaultResult(for: .selected)?.map(\.id)
        == ["CHF", "BTC", "EUR", "USD"])
    #expect(options.defaultResult(for: .synchronized) == nil)
    #expect(options.defaultResult(for: nil) == nil)
  }

  @Test func currencySearchKeepsCashRestrictionsLocalAndCatalogOrder() async throws {
    let currencies = CurrencyQuery(readInput: { ConverterState() })
    let cash = CashQuery(readInput: { ConverterState() })
    #expect(try await currencies.entities(matching: "jPy").items.map(\.id) == ["JPY"])
    let czechName = Locale.current.localizedString(forCurrencyCode: "CZK") ?? "CZK"
    #expect(try await currencies.entities(matching: czechName).items.contains { $0.id == "CZK" })
    let bitcoin = try await currencies.entities(matching: "Bitcoin").items.map(\.id)
    #expect(bitcoin == ["BTC", "BCH"])
    #expect(try await cash.entities(matching: "BTC").items.isEmpty)
    #expect(try await cash.entities(matching: "XAU").items.map(\.id) == ["XAU"])
    let localName = String(
      localized: "localCurrencyChoice", defaultValue: "Local currency", table: "Widgets")
    let local = currencyMatches(
      localName, allowsLocal: true, cashOnly: true, make: CashCurrency.init)
    #expect(local.items.contains { $0.id == WidgetSelection.localID })
    #expect(try await currencies.entities(matching: "").items.isEmpty)
  }

  @Test func iconChoicesRoundTripAndHaveRenderableSymbols() {
    let choices = CurrencySymbolChoice.allCases
    #expect(choices.count == CurrencySymbol.allCases.count)
    for choice in choices {
      #expect(UIImage(systemName: choice.symbol.rawValue) != nil)
      let restored = CurrencySymbolChoice(rawValue: choice.rawValue)
      #expect(restored?.symbol == choice.symbol)
      #expect(CurrencySymbolChoice.caseDisplayRepresentations[choice] != nil)
    }
  }
  @Test(arguments: [false, true], [nil, "12345678-1234-1234-1234-123456789012"] as [String?])
  func liveCompositionCountsCommittedDefaultAndCustomConversions(
    synchronized: Bool, instanceID: String?
  ) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = try RateStore(directory: directory).saveBootstrapRates(rates)
    let usage = ConversionUsageStore(directory: directory)
    for _ in 0..<2 { try usage.recordConversion() }
    var spec = WidgetSpec(
      kind: "CurrencyConverter", codes: ["EUR", "USD"], instanceID: instanceID,
      status: .notDetermined)
    spec.synchronized = synchronized
    try WidgetAction(WidgetCommand("7", spec: spec))
      .execute(using: WidgetComposition.action(directory: directory))
    #expect(try usage.claimReviewRequest())
    try WidgetAction(WidgetCommand("8", spec: spec))
      .execute(using: WidgetComposition.action(directory: directory))
    #expect(try !usage.claimReviewRequest())
  }

  @Test func reviewPersistenceFailureDoesNotFailCommittedWidgetInteraction() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = try RateStore(directory: directory).saveBootstrapRates(rates)
    let url = directory.appendingPathComponent("conversion-usage.json")
    let corrupt = Data("invalid".utf8)
    try corrupt.write(to: url)
    let spec = WidgetSpec(kind: "CurrencyConverter", codes: ["EUR", "USD"], status: .notDetermined)
    try WidgetAction(WidgetCommand("7", spec: spec))
      .execute(using: WidgetComposition.action(directory: directory))
    #expect(
      WidgetStore(directory: directory).widgetInput(key: spec.key, codes: spec.codes).amount == "7")
    #expect(try Data(contentsOf: url) == corrupt)
  }

  @Test(arguments: ["CurrencyCash", "CurrencyBoard"])
  func liveCompositionDoesNotCountNonCalculatorPresets(kind: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = try RateStore(directory: directory).saveBootstrapRates(rates)
    let usage = ConversionUsageStore(directory: directory)
    for _ in 0..<2 { try usage.recordConversion() }
    let spec = WidgetSpec(kind: kind, codes: ["EUR", "USD"], status: .notDetermined)
    try WidgetAction(WidgetCommand("preset:10", spec: spec))
      .execute(using: WidgetComposition.action(directory: directory))
    #expect(
      WidgetStore(directory: directory).widgetInput(key: spec.key, codes: spec.codes).amount == "10"
    )
    #expect(try !usage.claimReviewRequest())
  }

}
