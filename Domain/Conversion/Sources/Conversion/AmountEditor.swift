import ExchangeRates
import Foundation

/// Editable currency input shared by app rows and interactive widgets.
public struct AmountEditor: Codable, Equatable, Sendable {
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

  /// Creates normalized input for a currency list.
  public init(codes: [String], amount: String = "1") {
    var seen = Set<String>()
    let valid = codes.filter {
      (!CurrencySelection.normalize([$0], allowsLocal: true).isEmpty) && seen.insert($0).inserted
    }
    self.codes = valid.isEmpty ? ["EUR", "USD"] : valid
    active = self.codes.first(where: { $0 != "@local" }) ?? self.codes[0]
    self.amount =
      AmountEditing.parseAmount(amount).map { NSDecimalNumber(decimal: $0).stringValue } ?? "1"
    replacesOnDigit = true
  }

  /// Restores an existing editor state without resetting an in-progress edit.
  public init(
    codes: [String], active: String, amount: String,
    replacesOnDigit: Bool, editedAt: Date?
  ) {
    self.codes = codes
    self.active = active
    self.amount = amount
    self.replacesOnDigit = replacesOnDigit
    self.editedAt = editedAt
  }

  /// The parsed amount used for Decimal conversion.
  public var decimal: Decimal {
    Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
  }

  /// Selects a tile without changing its position; next digit starts a fresh amount.
  public mutating func select(_ code: String, snapshot: RateSnapshot) {
    guard codes.contains(code), code != CurrencySelection.localID else { return }
    // Reselecting the active tile starts fresh input and still counts as an interaction.
    replacesOnDigit = true
    editedAt = .now
    guard code != active else { return }
    let value = snapshot.convert(
      decimal, from: CurrencySelection.currency(active), to: CurrencySelection.currency(code))
    active = code
    // Missing conversion must never present the previous currency's value as this currency's value.
    amount = value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "0"
  }

  /// Applies only digits, decimal, clear, and deletion; no arithmetic commands.
  public mutating func press(_ key: String) {
    guard
      ["AC", "⌫", ".", ",", "00", "000"].contains(key)
        || (key.count == 1 && "0123456789".contains(key))
    else { return }
    defer { editedAt = .now }
    if key == "AC" { amount = "0"; replacesOnDigit = false; return }
    if key == "⌫" {
      if replacesOnDigit {
        amount = "0"
      } else {
        amount = amount.count > 1 ? String(amount.dropLast()) : "0"
      }
      replacesOnDigit = false
      return
    }
    if replacesOnDigit { amount = "0"; replacesOnDigit = false }
    if key == "." || key == "," {
      if !amount.contains(".") { amount += "." }
      return
    }
    for digit in key where amount.filter({ $0 != "." }).count < 14 {
      amount = amount == "0" ? String(digit) : amount + String(digit)
    }
  }

  /// Selects a trusted reference preset without opening a keyboard.
  public mutating func preset(_ value: Decimal) {
    guard !value.isNaN, value >= 0 else { return }
    amount = NSDecimalNumber(decimal: value).stringValue
    replacesOnDigit = true
    editedAt = .now
  }
}
