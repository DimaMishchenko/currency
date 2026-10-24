import Conversion
import ExchangeRates
import Foundation
import Testing

@testable import Widgets

@Suite struct WidgetCommandTests {
  @Test(arguments: [false, true])
  func persistedInactivityStartsFreshAndPublishesOnlyWhenSynchronized(synchronized: Bool) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    let app = ConversionStore(directory: directory)
    try app.updateInput { $0.setAmount("42") }
    var spec = WidgetSpec(kind: "CurrencyConverter", codes: ["EUR", "USD"], status: .notDetermined)
    spec.synchronized = synchronized
    try store.updateWidgetInput(key: spec.key, codes: spec.codes) { input in
      input.synchronize(with: app.input(), snapshot: snapshot)
      input.press("4", now: .distantPast)
      input.press("2", now: .distantPast)
    }
    #expect(try store.apply(WidgetCommand("7", spec: spec), snapshot: snapshot) == synchronized)
    #expect(store.widgetInput(key: spec.key, codes: spec.codes).amount == "7")
    #expect(app.input().amount == (synchronized ? "7" : "42"))
    try store.apply(WidgetCommand("8", spec: spec), snapshot: snapshot)
    #expect(store.widgetInput(key: spec.key, codes: spec.codes).amount == "78")
    #expect(app.input().amount == (synchronized ? "78" : "42"))
  }

  private var snapshot: RateSnapshot {
    RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-01-01", source: .init(provider: .ecb)),
      "USD": ExchangeRate(2, published: "2026-01-01", source: .init(provider: .ecb))
    ])
  }

  @Test func legacyCodecPreservesCommandsAndRejectsUnknownInput() {
    for key in WidgetCommand.Key.allCases {
      let action = WidgetCommand.Action.keypad(key)
      #expect(WidgetCommand.Action(legacyValue: action.legacyValue) == action)
    }
    for value in ["select:USD", "preset:100"] {
      #expect(WidgetCommand.Action(legacyValue: value)?.legacyValue == value)
    }
    for value in ["invalid", "preset:-1", "preset:1e3", "preset:NaN"] {
      #expect(WidgetCommand.Action(legacyValue: value) == nil)
    }
  }

  @Test func previewAndIndependentPersistenceUseSameReducerAfterResize() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    let spec = WidgetSpec(kind: "CurrencyConverter", codes: ["EUR", "USD"], status: .notDetermined)
    var preview = WidgetInput(codes: spec.codes)
    let actions = [
      WidgetCommand("7", spec: spec),
      WidgetCommand("2", spec: spec, activeCurrency: "USD", hiddenCurrency: "EUR"),
      WidgetCommand(".", spec: spec), WidgetCommand("5", spec: spec)
    ]
    for action in actions {
      action.apply(to: &preview, snapshot: snapshot)
      #expect(try !store.apply(action, snapshot: snapshot))
    }
    let saved = store.widgetInput(key: spec.key, codes: spec.codes)
    #expect(saved.codes == preview.codes)
    #expect(saved.active == preview.active)
    #expect(saved.amount == preview.amount)
    #expect(saved.replacesOnDigit == preview.replacesOnDigit)
    #expect(ConversionStore(directory: directory).input().amount == "1")
  }

  @Test func synchronizedSelectionStaysLocalAndEditingPublishes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    let app = ConversionStore(directory: directory)
    try app.updateInput { $0.setAmount("10") }
    var spec = WidgetSpec(kind: "CurrencyConverter", codes: ["EUR", "USD"], status: .notDetermined)
    spec.synchronized = true
    #expect(try !store.apply(WidgetCommand("select:USD", spec: spec), snapshot: snapshot))
    #expect(app.input().amount == "10")
    #expect(store.widgetInput(key: spec.key, codes: spec.codes).active == "USD")
    #expect(try store.apply(WidgetCommand("6", spec: spec), snapshot: snapshot))
    #expect(app.input().amount == "3")
    #expect(store.widgetInput(key: spec.key, codes: spec.codes).amount == "6")
  }

  @Test func requiredSnapshotFailsBeforePersistenceAndInvalidCommandIsInert() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    var spec = WidgetSpec(kind: "CurrencyConverter", codes: ["EUR", "USD"], status: .notDetermined)
    spec.synchronized = true
    #expect(throws: WidgetMutationError.ratesRequired) {
      try store.apply(WidgetCommand("7", spec: spec), snapshot: nil)
    }
    #expect(try !store.apply(WidgetCommand("invalid", spec: spec), snapshot: nil))
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }
  @Test(arguments: [false, true])
  func committedNumericConversionsNotifyAfterPersistence(synchronized: Bool) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    var spec = WidgetSpec(kind: "CurrencyConverter", codes: ["EUR", "USD"], status: .notDetermined)
    spec.synchronized = synchronized
    var notifications = 0
    for command in ["7", ".", "0", "select:USD", "AC", "⌫", "0", "invalid"] {
      try store.apply(WidgetCommand(command, spec: spec), snapshot: snapshot) {
        notifications += 1
        #expect(store.widgetInput(key: spec.key, codes: spec.codes).decimal > 0)
      }
    }
    #expect(notifications == 1)
    try store.apply(WidgetCommand("8", spec: spec), snapshot: snapshot) { notifications += 1 }
    #expect(notifications == 2)
  }

  @Test func missingDestinationRatesAndFailedCommitsNeverNotify() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    var spec = WidgetSpec(kind: "CurrencyConverter", codes: ["EUR", "USD"], status: .notDetermined)
    var notifications = 0
    try store.apply(WidgetCommand("7", spec: spec), snapshot: RateSnapshot()) {
      notifications += 1
    }
    spec.synchronized = true
    let url = directory.appendingPathComponent("input.json")
    let corrupt = Data("invalid".utf8)
    try corrupt.write(to: url)
    #expect(throws: (any Error).self) {
      try store.apply(WidgetCommand("8", spec: spec), snapshot: snapshot) { notifications += 1 }
    }
    #expect(notifications == 0)
    #expect(try Data(contentsOf: url) == corrupt)
  }

}
