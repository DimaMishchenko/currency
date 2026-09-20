import Conversion
import ExchangeRates
import Foundation
import LocalCurrency

/// Independent editable state for a configured interactive widget.
public struct WidgetInput: Codable, Equatable, Sendable {
  /// The configured tile order, unchanged when a tile becomes active.
  public private(set) var codes: [String]
  /// The currency currently receiving keypad input.
  public private(set) var active: String
  /// Editable, ungrouped decimal text.
  public private(set) var amount: String
  /// Whether the next digit starts a fresh value.
  public private(set) var replacesOnDigit: Bool
  /// The last accepted interaction time.
  public private(set) var editedAt: Date?

  private struct SharedValue: Codable, Equatable, Sendable {
    var source: String
    var amount: String
    var rate: Decimal?
  }
  private var sharedValue: SharedValue?

  private func sharedValue(for app: ConverterState, snapshot: RateSnapshot) -> SharedValue {
    SharedValue(
      source: app.source, amount: app.amount,
      rate: snapshot.convert(1, from: app.source, to: WidgetSelection.currency(active)))
  }

  /// Creates normalized input for a currency list.
  public init(codes: [String], amount: String = "1") {
    var seen = Set<String>()
    let valid = codes.filter {
      (!WidgetSelection.normalize([$0], allowsLocal: true).isEmpty) && seen.insert($0).inserted
    }
    self.codes = valid.isEmpty ? ["EUR", "USD"] : valid
    active = self.codes.first(where: { $0 != "@local" }) ?? self.codes[0]
    self.amount =
      WidgetMath.parseAmount(amount).map { NSDecimalNumber(decimal: $0).stringValue } ?? "1"
    replacesOnDigit = true
  }

  /// Reconciles a synchronized list without resetting an amount in a surviving active currency.
  public mutating func reconcile(codes: [String]) {
    let normalized = WidgetInput(codes: codes).codes
    guard normalized != self.codes else { return }
    self.codes = normalized
    if !normalized.contains(active) {
      sharedValue = nil
      active = normalized.first(where: { $0 != "@local" }) ?? normalized[0]
      amount = "1"
      replacesOnDigit = true
    }
  }

  /// Shares value with the app while retaining this widget's active tile.
  public mutating func synchronize(with app: ConverterState, snapshot: RateSnapshot) {
    let incoming = sharedValue(for: app, snapshot: snapshot)
    guard sharedValue != incoming else { return }
    sharedValue = incoming
    let currency = WidgetSelection.currency(active)
    if currency == app.source {
      if amount != app.amount { amount = app.amount; replacesOnDigit = true }
    } else if let value = snapshot.convert(app.decimal, from: app.source, to: currency) {
      if decimal != value {
        amount = NSDecimalNumber(decimal: value).stringValue; replacesOnDigit = true
      }
    }
    // Without a conversion rate, keep the selected tile editable; other values remain unavailable.
  }

  /// Publishes the value and remembers its exact source representation to avoid round-trip resets.
  public mutating func publish(to app: inout ConverterState, snapshot: RateSnapshot) {
    let source = WidgetSelection.currency(active)
    if source == app.source {
      app.setRoundedAmount(decimal)
    } else if let value = snapshot.convert(decimal, from: source, to: app.source) {
      app.setRoundedAmount(value)
    }
    sharedValue = sharedValue(for: app, snapshot: snapshot)
  }

  /// The parsed amount used for Decimal conversion.
  public var decimal: Decimal {
    Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
  }

  /// A size-dependent prefix; Default reserves its last visible slot for Local.
  /// This presentation list must never replace the canonical saved codes.
  public func visibleCodes(limit: Int, reservesLocal: Bool = false) -> [String] {
    guard limit > 0 else { return [] }
    if reservesLocal, let local = codes.first(where: { WidgetSelection.isLocal($0) }),
      codes.count > limit
    {
      return Array(codes.filter { $0 != local }.prefix(limit - 1)) + [local]
    }
    return Array(codes.prefix(limit))
  }

  /// Projects hidden active input into a visible currency without mutating stored input.
  /// With no available conversion, retain the original value and leave the keypad disabled.
  public func displayedInput(
    limit: Int, reservesLocal: Bool = false, snapshot: RateSnapshot
  ) -> WidgetInput {
    let visible = visibleCodes(limit: limit, reservesLocal: reservesLocal)
    guard !visible.contains(active),
      let target = visible.first(where: {
        $0 != WidgetSelection.localID
          && snapshot.convert(
            decimal, from: WidgetSelection.currency(active), to: WidgetSelection.currency($0))
            != nil
      })
    else { return self }
    var display = self
    display.select(target, snapshot: snapshot)
    return display
  }

  private var editor: AmountEditor {
    get {
      AmountEditor(
        codes: codes, active: active, amount: amount,
        replacesOnDigit: replacesOnDigit, editedAt: editedAt)
    }
    set {
      active = newValue.active
      amount = newValue.amount
      replacesOnDigit = newValue.replacesOnDigit
      editedAt = newValue.editedAt
    }
  }

  /// Selects a tile without changing its position; next digit starts a fresh amount.
  public mutating func select(_ code: String, snapshot: RateSnapshot) {
    editor.select(code, snapshot: snapshot)
  }

  /// Applies a currency amount editing command.
  public mutating func press(_ key: String) { editor.press(key) }

  /// Selects a trusted reference preset without opening a keyboard.
  public mutating func preset(_ value: Decimal) { editor.preset(value) }
}

/// Pure presentation rules shared by widget timelines and tests.
public enum WidgetMath {
  /// Parses a configured amount using the shared editable-amount policy.
  public static func parseAmount(_ text: String) -> Decimal? { AmountEditing.parseAmount(text) }

  /// Chooses the first familiar amount whose conversion reaches at least ten target units.
  public static func anchor(rate: Decimal) -> Decimal? {
    guard !rate.isNaN, rate > 0 else { return nil }
    let candidates: [Decimal] = [1, 5, 10, 20, 50, 100, 500, 1000, 5000, 10000, 100000, 1000000]
    return candidates.first { $0 * rate >= 10 } ?? candidates.last
  }

  /// A rounded, two-significant-digit mental conversion rule and its relative error.
  public static func rule(rate: Decimal) -> (divide: Bool, factor: Decimal, error: Decimal)? {
    guard !rate.isNaN, rate > 0 else { return nil }
    let divide = rate < 1
    var factor = divide ? 1 / rate : rate
    guard !factor.isNaN else { return nil }
    var scale = 0
    var magnitude = factor
    while magnitude >= 100 && scale > -30 { magnitude /= 10; scale -= 1 }
    if magnitude < 10 { scale += 1 }
    var rounded = Decimal()
    NSDecimalRound(&rounded, &factor, scale, .plain)
    guard rounded > 0 else { return nil }
    let approximation = divide ? 1 / rounded : rounded
    let difference = approximation > rate ? approximation - rate : rate - approximation
    return (divide, rounded, difference / rate)
  }

}
