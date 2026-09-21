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

  @Test func recentlyEditedTimelineAvoidsRefreshAndPreservesCurrentInput() async {
    let calls = Mutex(0)
    var input = WidgetInput(codes: ["EUR", "USD"])
    input.press("7")
    let current = input
    let now = Date.now
    let rates = rates
    let dependencies = WidgetTimelineDependencies(
      input: { ConverterState() }, rates: { rates }, location: { nil },
      locationStatus: { .notDetermined }, widgetInput: { _, _, _ in current },
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
      input: { ConverterState() }, rates: { rates }, location: { nil },
      locationStatus: { .notDetermined },
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
    let dependencies = WidgetTimelineDependencies(
      input: { ConverterState() }, rates: { rates }, location: { location },
      locationStatus: { .available },
      widgetInput: { _, codes, amount in WidgetInput(codes: codes, amount: amount) },
      refreshRates: { _ in RefreshResult(snapshot: rates, warning: nil) },
      refreshLocalCurrency: {}, now: { now })
    let settings = AnchorSettings()
    settings.comparison = WidgetCurrency("@local")
    let provider = SuiteTimeline<AnchorSettings>(
      kind: "CurrencyPocketRate", dependencies: dependencies)
    let timeline = provider.timeline(starting: provider.entry(settings))
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
      reloadSynchronizedWidgets: { reloads.withLock { $0 += 1 } })
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
      reloadSynchronizedWidgets: { reloads.withLock { $0 += 1 } })
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
      reloadSynchronizedWidgets: { Issue.record("Custom input must not reload unrelated widgets") })
    let spec = WidgetSpec(kind: "CurrencyCash", codes: ["EUR", "USD"], status: .notDetermined)
    try WidgetAction(WidgetCommand("7", spec: spec)).execute(using: dependencies)
    #expect(reads.withLock { $0 } == 0)
    #expect(seen.withLock { $0 } == spec.key)
  }

  @Test func customBoardPickerPreservesLocalThroughSelectionSearchAndConversion() async throws {
    let query = BoardCurrencyQuery(readInput: { ConverterState() })
    let choices = try await query.suggestedEntities()
    #expect(choices.items.contains { $0.id == WidgetSelection.localID })
    let localName = String(
      localized: "localCurrencyChoice", defaultValue: "Local currency", table: "Widgets")
    let matches = try await query.entities(matching: localName)
    #expect(matches.items.contains { $0.id == WidgetSelection.localID })
    let restored = try await query.entities(for: ["USD", WidgetSelection.localID])
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
}
