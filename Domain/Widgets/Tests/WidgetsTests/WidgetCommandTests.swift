import Conversion
import ExchangeRates
import Foundation
import Testing

@testable import Widgets

@Suite struct WidgetCommandTests {
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
}
