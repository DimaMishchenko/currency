import AppIntents
import CurrencySupport
import Foundation
import OSLog

/// Widget-only mutations; never touches the app converter's input.
struct WidgetAction: AppIntent {
  static let isDiscoverable = false
  private static let logger = Logger(
    subsystem: "com.dimasike.currency", category: "WidgetInteraction")

  static let title: LocalizedStringResource = LocalizedStringResource(
    "actionTitle", defaultValue: "Update currency widget", table: "Widgets")
  @Parameter(
    title: LocalizedStringResource("stateParameter", defaultValue: "State", table: "Widgets"))
  var stateKey: String
  @Parameter(
    title: LocalizedStringResource(
      "currenciesParameter", defaultValue: "Currencies", table: "Widgets")) var codes: [String]
  @Parameter(
    title: LocalizedStringResource("commandParameter", defaultValue: "Command", table: "Widgets"))
  var command: String
  @Parameter(
    title: LocalizedStringResource(
      "initialParameter", defaultValue: "Initial amount", table: "Widgets")) var initialAmount:
    String
  init() {}
  init(_ command: String, spec: WidgetSpec) {
    self.command = command
    stateKey = spec.key
    codes = spec.codes
    initialAmount = spec.amount
  }

  func perform() async throws -> some IntentResult {
    let start = ContinuousClock.now
    defer {
      Self.logger.debug(
        "Widget mutation completed in \(start.duration(to: .now).description, privacy: .public)")
    }
    let store = CurrencyStore.shared
    // Digits and presets only change input; only currency selection needs conversion rates.
    let snapshot = command.hasPrefix("select:") ? store.loadRates() : nil
    try store.updateWidgetInput(key: stateKey, codes: codes, amount: initialAmount) { input in
      if command.hasPrefix("select:"), let snapshot {
        input.select(String(command.dropFirst(7)), snapshot: snapshot)
      } else if command.hasPrefix("preset:"),
        let amount = WidgetMath.parseAmount(String(command.dropFirst(7))),
        WidgetPresets.amounts(codes.first ?? "EUR").contains(amount)
      {
        input.preset(amount)
      } else {
        input.press(command)
      }
    }
    // WidgetKit reloads the interacted widget after perform returns.
    return .result()
  }
}
