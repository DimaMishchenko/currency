import Conversion
import ExchangeRates
import Foundation
import LocalCurrency
import Testing

@testable import Home

private struct SlowFeedbackProvider: RateProvider {
  func fetch() async throws -> [String: ExchangeRate] {
    try await Task.sleep(for: .seconds(30))
    return [:]
  }
}

@MainActor
struct HomeEditingTests {
  @Test func locationReloadPreservesValidEditorAndClosesOnlyRemovedLocalCurrency() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HomeTestStore(directory: directory)
    try store.updateInput {
      $0.setDestinations(["USD"]); $0.setUsesLocalCurrency(true)
    }
    try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
    let model = makeHomeModel(store: store, service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "CZK": ExchangeRate(25, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    model.beginEditing("USD")
    model.reloadInput(preservingEditor: true)
    #expect(model.editor != nil)
    #expect(model.editingCode == "USD")
    model.beginEditing("CZK", selectionID: CurrencySelection.localID)
    try store.saveWidgetLocation(WidgetLocation(country: "GB", currency: "GBP"))
    model.reloadInput(preservingEditor: true)
    #expect(model.editor == nil)
    #expect(model.input.destinations == ["USD", "GBP"])
  }

  @Test func localEditorTracksSelectionRatherThanMatchingFixedCurrency() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HomeTestStore(directory: directory)
    try store.updateInput {
      $0.setDestinations(["CZK"]); $0.setUsesLocalCurrency(true)
    }
    try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
    let model = makeHomeModel(store: store, service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "CZK": ExchangeRate(25, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    model.beginEditing("CZK", selectionID: CurrencySelection.localID)
    #expect(model.editingSelectionID == CurrencySelection.localID)
    #expect(model.press("2"))
    #expect(model.input.destinationRows.count == 2)
    try store.saveWidgetLocation(WidgetLocation(country: "GB", currency: "GBP"))
    model.reloadInput(preservingEditor: true)
    #expect(model.editor == nil)
    model.beginEditing("CZK")
    try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
    model.reloadInput(preservingEditor: true)
    #expect(model.editor != nil)
    #expect(model.editingSelectionID == "CZK")
    #expect(model.updateInput { $0.removeDestination("CZK") })
    #expect(model.editor == nil)
    #expect(model.input.usesLocalCurrency)
    #expect(model.updateInput { $0.changeSource("CZK") })
    model.beginEditing("CZK", selectionID: CurrencySelection.localID)
    #expect(model.editor != nil)
    #expect(model.editingSelectionID == CurrencySelection.localID)
    #expect(model.press("3"))
    #expect(model.updateInput { $0.removeDestination(CurrencySelection.localID) })
    #expect(model.editor == nil)
    #expect(model.input.source == "CZK")
  }

  @Test func secondaryEditingKeepsBaseAndOrderAndPersistsValue() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HomeTestStore(directory: directory)
    let model = makeHomeModel(store: store, service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "GBP": ExchangeRate(4, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    let order = model.input.destinations
    let original = model.input
    model.beginEditing("USD")
    #expect(model.input == original)
    #expect(model.press("2"))
    #expect(model.press("5"))
    #expect(model.input.source == "EUR")
    #expect(model.input.destinations == order)
    #expect(model.input.decimal == Decimal(string: "12.5"))
    #expect(store.input() == model.input)
    model.beginEditing("GBP")
    #expect(model.editingText == "50")
    #expect(model.press("."))
    #expect(model.press("1"))
    #expect(model.input.decimal == Decimal(string: "0.025"))
    model.endEditing()
    #expect(model.editor == nil)
    model.beginEditing("EUR")
    #expect(model.press("7"))
    #expect(model.input.amount == "7")
    model.beginEditing("JPY")
    #expect(model.editingCode == "EUR")
    model.reloadInput()
    #expect(model.editor == nil)
  }

  @Test func switchingRowsPreservesRepeatingDecimalConversion() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = makeHomeModel(store: HomeTestStore(directory: directory), service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(3, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "GBP": ExchangeRate(6, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    model.beginEditing("USD")
    #expect(model.press("1"))
    #expect(model.input.amount.count > 30)
    model.beginEditing("GBP")
    #expect(model.editingText == "2")
    #expect(model.input.source == "EUR")
  }

  @Test func removingActiveCurrencyClosesEditor() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = makeHomeModel(store: HomeTestStore(directory: directory), service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    model.beginEditing("USD")
    #expect(model.editor != nil)
    #expect(model.updateInput { $0.setDestinations($0.destinations.filter { $0 != "USD" }) })
    #expect(model.editor == nil)
    let saved = model.input
    #expect(!model.press("7"))
    #expect(model.input == saved)
  }

  @Test func editingUsesLatestSharedBase() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HomeTestStore(directory: directory)
    let model = makeHomeModel(store: store, service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "GBP": ExchangeRate(4, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    model.beginEditing("USD")
    try store.updateInput { $0.changeSource("GBP") }
    #expect(model.press("5"))
    #expect(model.input.source == "GBP")
    #expect(model.input.decimal == 10)
    #expect(store.input() == model.input)
    try store.updateInput { $0.setDestinations($0.destinations.filter { $0 != "USD" }) }
    let saved = store.input()
    #expect(!model.press("7"))
    #expect(store.input() == saved)
  }

  @Test func failedSecondaryEditKeepsDisplayedAndSavedAmounts() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let model = makeHomeModel(store: HomeTestStore(directory: file), service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    model.beginEditing("USD")
    #expect(model.editor != nil)
    let before = model.editor
    let saved = model.input
    #expect(!model.press("7"))
    #expect(model.editor == before)
    #expect(model.input == saved)
  }

  @Test func cancelledManualRefreshClearsIndicatorWithoutError() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = makeHomeModel(
      store: HomeTestStore(directory: directory),
      service: RateService(fiat: SlowFeedbackProvider(), daily: SlowFeedbackProvider(), crypto: nil)
    )
    let task = Task { await model.refresh(force: true) }
    for _ in 0..<100 where !model.refreshing { await Task.yield() }
    #expect(model.manuallyRefreshing)
    task.cancel()
    await task.value
    #expect(!model.refreshing)
    #expect(!model.manuallyRefreshing)
    #expect(model.warning == nil)
  }

  @Test func failedInputSaveDoesNotReportSuccessfulMutation() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let model = makeHomeModel(store: HomeTestStore(directory: file), service: RateService())
    let original = model.input
    #expect(!model.updateInput { $0.press("7") })
    #expect(model.input == original)
    #expect(model.warning != nil)
  }
}
