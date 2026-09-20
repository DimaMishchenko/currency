import Conversion
import ExchangeRates
import Foundation

/// A host-independent interaction with a configured currency widget.
public struct WidgetCommand: Sendable {
  /// Supported keypad inputs, preserving the installed intent encoding.
  public enum Key: String, CaseIterable, Sendable {
    case zero = "0", one = "1", two = "2", three = "3", four = "4"
    case five = "5", six = "6", seven = "7", eight = "8", nine = "9"
    case doubleZero = "00", tripleZero = "000", decimal = ".", comma = ","
    case clear = "AC", delete = "⌫"
  }

  /// Semantic interaction decoded from the legacy AppIntent string parameter.
  public enum Action: Equatable, Sendable {
    case selectCurrency(String)
    case preset(Decimal)
    case keypad(Key)

    /// Decodes an existing intent parameter without accepting unknown editing commands.
    public init?(legacyValue: String) {
      if legacyValue.hasPrefix("select:") {
        self = .selectCurrency(String(legacyValue.dropFirst(7)))
      } else if legacyValue.hasPrefix("preset:"),
        let amount = AmountEditing.parseAmount(String(legacyValue.dropFirst(7)))
      {
        self = .preset(amount)
      } else if let key = Key(rawValue: legacyValue) {
        self = .keypad(key)
      } else {
        return nil
      }
    }

    /// Encodes the unchanged installed AppIntent parameter format.
    public var legacyValue: String {
      switch self {
      case .selectCurrency(let code): "select:" + code
      case .preset(let amount): "preset:" + NSDecimalNumber(decimal: amount).stringValue
      case .keypad(let key): key.rawValue
      }
    }
  }

  /// The persisted AppIntent parameter encoding.
  public let command: String
  /// Canonical configuration associated with the control.
  public let spec: WidgetSpec
  /// Visible currency to activate after a widget resize.
  public let activeCurrency: String?
  /// Previously active currency hidden by the new size.
  public let hiddenCurrency: String?
  /// Decoded semantic action; unknown commands remain inert.
  public var action: Action? { Action(legacyValue: command) }
  /// Whether the action changes only this widget's active tile.
  public var changesSelection: Bool {
    if case .selectCurrency = action { return true }
    return false
  }
  /// Whether applying this action requires cached conversion rates.
  public var requiresSnapshot: Bool {
    spec.synchronized || changesSelection || activeCurrency != nil
  }

  /// Creates an event from the installed intent codec without executing it.
  public init(
    _ command: String, spec: WidgetSpec, activeCurrency: String? = nil,
    hiddenCurrency: String? = nil
  ) {
    self.command = command
    self.spec = spec
    self.activeCurrency = activeCurrency
    self.hiddenCurrency = hiddenCurrency
  }

  /// Creates an event from a typed presentation action.
  public init(
    action: Action, spec: WidgetSpec, activeCurrency: String? = nil,
    hiddenCurrency: String? = nil
  ) {
    self.init(
      action.legacyValue, spec: spec, activeCurrency: activeCurrency,
      hiddenCurrency: hiddenCurrency)
  }

  /// Applies the same reduction to persisted input or an isolated tutorial state.
  public func apply(to input: inout WidgetInput, snapshot: RateSnapshot?) {
    guard let action else { return }
    if let activeCurrency, input.active == hiddenCurrency, input.active != activeCurrency,
      let snapshot
    {
      input.select(activeCurrency, snapshot: snapshot)
    }
    switch action {
    case .selectCurrency(let code):
      if let snapshot { input.select(code, snapshot: snapshot) }
    case .preset(let amount):
      if WidgetPresets.amounts(spec.codes.first ?? "EUR").contains(amount) {
        input.preset(amount)
      }
    case .keypad(let key): input.press(key.rawValue)
    }
  }
}

/// Failure to supply the cached rates required by a widget interaction.
public enum WidgetMutationError: Error, Equatable, Sendable {
  case ratesRequired
}

extension WidgetStore {
  /// Applies an intent under the existing app-then-widget lock ordering.
  /// Returns whether synchronized widgets need invalidation after a successful commit.
  @discardableResult
  public func apply(
    _ action: WidgetCommand, key: String? = nil, snapshot: RateSnapshot?
  ) throws -> Bool {
    guard action.action != nil else { return false }
    if action.requiresSnapshot && snapshot == nil { throw WidgetMutationError.ratesRequired }
    let spec = action.spec
    let key = key ?? spec.key
    let conversion = ConversionStore(directory: directory)
    if spec.synchronized, let snapshot {
      guard action.changesSelection else {
        try conversion.updateInput { app in
          try updateWidgetInput(key: key, codes: spec.codes, amount: spec.amount) { input in
            input.synchronize(with: app, snapshot: snapshot)
            action.apply(to: &input, snapshot: snapshot)
            input.publish(to: &app, snapshot: snapshot)
          }
        }
        return true
      }
      let app = conversion.input()
      try updateWidgetInput(key: key, codes: spec.codes, amount: spec.amount) { input in
        input.synchronize(with: app, snapshot: snapshot)
        action.apply(to: &input, snapshot: snapshot)
      }
    } else {
      try updateWidgetInput(key: key, codes: spec.codes, amount: spec.amount) { input in
        action.apply(to: &input, snapshot: snapshot)
      }
    }
    return false
  }
}
