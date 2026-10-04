import AppIntents
import Conversion
import ExchangeRatesUI
import Foundation
import LocalCurrency
import OSLog
import WidgetKit
import Widgets
import WidgetsUI

/// Default uses app input; Custom mutations stay in configured widget storage.
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
  @Parameter(title: "Synchronized", default: false) var synchronized: Bool
  @Parameter(title: "Active currency") var activeCurrency: String?
  @Parameter(title: "Hidden currency") var hiddenCurrency: String?
  init() {}
  init(_ command: WidgetCommand) {
    self.init(
      command.command, spec: command.spec,
      activeCurrency: command.activeCurrency, hiddenCurrency: command.hiddenCurrency)
  }
  init(
    _ command: String, spec: WidgetSpec, activeCurrency: String? = nil,
    hiddenCurrency: String? = nil
  ) {
    self.hiddenCurrency = hiddenCurrency
    self.activeCurrency = activeCurrency
    self.command = command
    stateKey = spec.key
    codes = spec.codes
    initialAmount = spec.amount
    synchronized = spec.synchronized
  }

  func perform() async throws -> some IntentResult {
    let start = ContinuousClock.now
    defer {
      Self.logger.debug(
        "Widget mutation completed in \(start.duration(to: .now).description, privacy: .public)")
    }
    try execute(using: WidgetComposition.action())
    // WidgetKit reloads the interacted widget after perform returns.
    return .result()
  }

  /// Runs the production adapter with controlled capabilities in integration tests.
  func execute(using dependencies: WidgetActionDependencies) throws {
    var spec = WidgetSpec(
      kind: "", codes: codes, amount: initialAmount, status: .notDetermined)
    // AppIntent parameters already carry the resolved selection shown by the tapped control.
    spec.codes = codes
    spec.synchronized = synchronized
    let action = WidgetCommand(
      command, spec: spec, activeCurrency: activeCurrency, hiddenCurrency: hiddenCurrency)
    let snapshot = action.requiresSnapshot ? dependencies.rates() : nil
    if try dependencies.apply(action, stateKey, snapshot) {
      dependencies.reloadSynchronizedWidgets()
    }
  }

}
