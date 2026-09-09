import AppIntents
import CurrencySupport
import Foundation
import OSLog
import WidgetKit
import WidgetPresentation

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
    let store = CurrencyStore.shared
    // Read cached rates only for conversion, Default publishing, or a resized selection.
    let changesSelection = command.hasPrefix("select:")
    let snapshot =
      synchronized || changesSelection || activeCurrency != nil ? store.loadRates() : nil
    func mutate(_ input: inout WidgetInput) {
      if let activeCurrency, input.active == hiddenCurrency, input.active != activeCurrency,
        let snapshot
      {
        input.select(activeCurrency, snapshot: snapshot)
      }
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
    if synchronized, let rates = snapshot {
      if changesSelection {
        // Selection only touches this widget. Do not rewrite app input or reload other widgets.
        let app = store.input()
        try store.updateWidgetInput(key: stateKey, codes: codes, amount: initialAmount) { input in
          input.synchronize(with: app, snapshot: rates)
          mutate(&input)
        }
      } else {
        try store.updateInput { app in
          try store.updateWidgetInput(key: stateKey, codes: codes, amount: initialAmount) { input in
            input.synchronize(with: app, snapshot: rates)
            mutate(&input)
            input.publish(to: &app, snapshot: rates)
          }
        }
        for kind in ["CurrencyConverter", "CurrencyBoard", "CurrencyQuickRate"] {
          WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
      }
    } else {
      try store.updateWidgetInput(
        key: stateKey, codes: codes, amount: initialAmount, mutation: mutate)
    }
    // WidgetKit reloads the interacted widget after perform returns.
    return .result()
  }
}
