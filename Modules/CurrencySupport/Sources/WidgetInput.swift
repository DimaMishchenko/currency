import ExchangeRates
import Foundation

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

  /// Creates normalized input for a currency list.
  public init(codes: [String], amount: String = "1") {
    var seen = Set<String>()
    let valid = codes.filter { CurrencyCatalog.codes.contains($0) && seen.insert($0).inserted }
    self.codes = valid.isEmpty ? ["EUR", "USD"] : valid
    active = self.codes[0]
    self.amount =
      WidgetMath.parseAmount(amount).map { NSDecimalNumber(decimal: $0).stringValue } ?? "1"
    replacesOnDigit = true
  }

  /// The parsed amount used for Decimal conversion.
  public var decimal: Decimal {
    Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
  }

  /// Keeps the active currency visible when a smaller widget cannot fit the whole list.
  /// Fixed pages preserve tile positions when selecting another currency on the same page.
  public func visibleCodes(limit: Int) -> [String] {
    guard limit > 0 else { return [] }
    let start = ((codes.firstIndex(of: active) ?? 0) / limit) * limit
    return Array(codes.dropFirst(start).prefix(limit))
  }

  /// Selects a tile without changing its position; next digit starts a fresh amount.
  public mutating func select(_ code: String, snapshot: RateSnapshot) {
    guard codes.contains(code) else { return }
    // Reselecting the active tile starts fresh input and still counts as an interaction.
    replacesOnDigit = true
    editedAt = .now
    guard code != active else { return }
    let value = snapshot.convert(decimal, from: active, to: code)
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

/// Pure presentation rules shared by widget timelines and tests.
public enum WidgetMath {
  /// Parses a nonnegative configured amount without accepting grouping or exponent syntax.
  public static func parseAmount(_ text: String) -> Decimal? {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: ".")
    guard !normalized.isEmpty, normalized.count <= 30,
      normalized.allSatisfy({ "0123456789.".contains($0) }),
      normalized.filter({ $0 == "." }).count <= 1,
      let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
      !value.isNaN, value >= 0
    else { return nil }
    return value
  }

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
