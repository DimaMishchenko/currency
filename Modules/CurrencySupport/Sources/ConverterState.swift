import ExchangeRates
import Foundation

/// The persisted converter input shared by the app and widgets.
public struct ConverterState: Codable, Sendable, Equatable {
  /// The user's ordered destination currencies.
  private var savedTargets: [String]? = nil
  /// The time of the most recent input edit.
  public private(set) var editedAt: Date? = nil
  /// The source amount as editable decimal text.
  public private(set) var amount = "1"
  /// The source currency code.
  public private(set) var source = "EUR"
  /// The primary destination currency code.
  public private(set) var primaryDestination = "USD"
  private enum CodingKeys: String, CodingKey {
    case savedTargets, editedAt, amount
    case source = "from"
    case primaryDestination = "to"
  }

  /// Creates the default converter input.
  public init() {}
  /// The source amount parsed as a decimal value.
  public var decimal: Decimal {
    Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
  }

  /// Applies a keypad command to the input.
  public mutating func press(_ key: String) {
    let previousAmount = amount
    let previousSource = source
    defer {
      if amount != previousAmount || source != previousSource { editedAt = Date() }
    }
    switch key {
    case "00":
      press("0")
      press("0")
    case "AC": amount = "0"
    case "⌫": amount = amount.count > 1 ? String(amount.dropLast()) : "0"
    case "⇅": changeSource(primaryDestination)
    case ".", ",": if !amount.contains(".") { amount += "." }
    default:
      guard key.count == 1, "0123456789".contains(key), amount.filter({ $0 != "." }).count < 14
      else { return }
      if amount == "0" { amount = key } else { amount += key }
    }
  }
}

extension ConverterState {
  /// The normalized ordered destination currencies.
  public var destinations: [String] {
    var seen = Set<String>()
    return (savedTargets ?? [primaryDestination, "GBP", "CZK", "JPY", "CHF", "BTC"])
      .filter {
        $0 != source && CurrencyCatalog.codes.contains($0) && seen.insert($0).inserted
      }
  }

  /// Replaces and normalizes the destination currencies.
  public mutating func setDestinations(_ codes: [String]) {
    savedTargets = codes
    savedTargets = destinations
    primaryDestination = destinations.first ?? source
  }

  /// Promotes a destination to the source while preserving its converted value.
  public mutating func useAsBase(_ code: String, snapshot: RateSnapshot) {
    guard code != source, CurrencyCatalog.codes.contains(code),
      let converted = snapshot.convert(decimal, from: source, to: code)
    else { return }
    var value = converted
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, CurrencyDisplay.fractionDigits(code), .plain)
    let oldSource = source
    let updated = destinations.map { $0 == code ? oldSource : $0 }
    source = code
    amount = NSDecimalNumber(decimal: rounded).stringValue
    setDestinations(updated)
    editedAt = Date()
  }

  /// Changes the source currency and preserves destination ordering.
  public mutating func changeSource(_ code: String) {
    guard CurrencyCatalog.codes.contains(code), code != source else { return }
    let oldSource = source
    let updated = destinations.map { $0 == code ? oldSource : $0 }
    source = code
    setDestinations(updated)
  }
}

extension ConverterState {
  /// Moves existing destinations before an anchor, preserving concurrently added currencies.
  /// A missing anchor places the moved currencies at the end.
  public mutating func moveDestinations(_ codes: [String], before anchor: String?) {
    let moving = codes.filter { destinations.contains($0) }
    var remaining = destinations.filter { !moving.contains($0) }
    let index = anchor.flatMap { remaining.firstIndex(of: $0) } ?? remaining.endIndex
    remaining.insert(contentsOf: moving, at: index)
    setDestinations(remaining)
  }
}
