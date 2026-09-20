import ExchangeRates
import Foundation
import LocalCurrency

/// The persisted converter input shared by the app and widgets.
public struct ConverterState: Codable, Sendable, Equatable {
  /// The user's ordered destination currencies.
  private var savedTargets: [String]? = nil
  private var followsLocalCurrency: Bool? = nil
  /// Whether the converter retains a dynamic Local selection.
  public var usesLocalCurrency: Bool { followsLocalCurrency == true }
  /// The permitted observation, resolved when the store loads input; never persisted as a selection.
  public private(set) var localCurrencyCode: String?
  /// Whether the observation needs a refresh.
  public private(set) var localCurrencyIsStale = false
  /// The time of the most recent input edit.
  public private(set) var editedAt: Date? = nil
  /// The source amount as editable decimal text.
  public private(set) var amount = "1"
  /// The source currency code.
  public private(set) var source = "EUR"
  /// The primary destination currency code.
  public private(set) var primaryDestination = "USD"
  private enum CodingKeys: String, CodingKey {
    case savedTargets, editedAt, amount, followsLocalCurrency
    case source = "from"
    case primaryDestination = "to"
  }

  /// Creates the default converter input.
  public init() {}
  /// The source amount parsed as a decimal value.
  public var decimal: Decimal {
    Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
  }

  /// Updates the shared value without changing the app's currency selection.
  public mutating func setAmount(_ text: String) {
    guard AmountEditing.parseAmount(text) != nil else { return }
    amount = text
    editedAt = .now
  }

  /// Stores a converted value without rounding away small secondary-currency edits.
  public mutating func setConvertedAmount(_ value: Decimal) {
    guard !value.isNaN, value >= 0 else { return }
    amount = NSDecimalNumber(decimal: value).stringValue
    editedAt = .now
  }

  /// Stores an externally supplied value with the app's editable precision.
  public mutating func setRoundedAmount(_ value: Decimal) {
    guard !value.isNaN, value >= 0 else { return }
    var value = value
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 2, .plain)
    amount = NSDecimalNumber(decimal: rounded).stringValue
    editedAt = .now
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
  /// The explicitly chosen destination currencies, independent of Local.
  public var manualDestinations: [String] {
    var seen = Set<String>()
    return (savedTargets ?? [primaryDestination, "GBP", "CZK", "JPY", "CHF", "BTC"])
      .filter {
        $0 != source && CurrencyCatalog.codes.contains($0) && seen.insert($0).inserted
      }
  }

  /// Unique resolved codes used for calculations and rate requests.
  public var destinations: [String] {
    CurrencySelection.normalize(
      manualDestinations + (usesLocalCurrency ? [localCurrencyCode].compactMap { $0 } : [])
    )
    .filter { $0 != source }
  }

  /// A displayed selection, whose identity stays independent of its resolved currency.
  public struct Destination: Identifiable, Equatable, Sendable {
    /// The fixed currency code or the stable Local selection identifier.
    public let id: String
    /// The currently resolved ISO currency code.
    public let code: String
    /// Whether this selection follows the device location.
    public var isLocal: Bool { id == CurrencySelection.localID }
  }

  /// Separate fixed and dynamic rows, even when Local matches a fixed row or the base.
  public var destinationRows: [Destination] {
    var rows = manualDestinations.map { Destination(id: $0, code: $0) }
    if usesLocalCurrency, let localCurrencyCode {
      rows.append(Destination(id: CurrencySelection.localID, code: localCurrencyCode))
    }
    return rows
  }

  /// Enables or removes the dynamic Local selection without changing explicit currencies.
  public mutating func setUsesLocalCurrency(_ enabled: Bool) { followsLocalCurrency = enabled }

  /// Resolves Local from shared permission and cache state.
  public mutating func resolveLocalCurrency(
    _ location: WidgetLocation?, status: WidgetLocationStatus
  ) {
    let resolved = ResolvedCurrencySelection(
      codes: [CurrencySelection.localID], location: location, status: status)
    localCurrencyCode = resolved.localCode
    localCurrencyIsStale = resolved.localIsStale
  }

  /// Removes exactly one selection; Local is addressed by its stable selection ID.
  public mutating func removeDestination(_ id: String) {
    if id == CurrencySelection.localID {
      setUsesLocalCurrency(false)
    } else {
      setDestinations(manualDestinations.filter { $0 != id })
    }
  }

  /// Replaces and normalizes the destination currencies.
  public mutating func setDestinations(_ codes: [String]) {
    savedTargets = codes
    savedTargets = manualDestinations
    primaryDestination = destinations.first ?? source
  }

  /// Promotes a destination to the source while preserving its converted value.
  public mutating func useAsBase(_ code: String, snapshot: RateSnapshot) {
    guard code != source, CurrencyCatalog.codes.contains(code),
      let converted = snapshot.convert(decimal, from: source, to: code)
    else { return }
    var value = converted
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, CurrencyPrecision.fractionDigits(code), .plain)
    let oldSource = source
    var updated = manualDestinations.map { $0 == code ? oldSource : $0 }
    if usesLocalCurrency && localCurrencyCode == code && !manualDestinations.contains(code) {
      updated.append(oldSource)
    }
    source = code
    amount = NSDecimalNumber(decimal: rounded).stringValue
    setDestinations(updated)
    editedAt = Date()
  }

  /// Changes the source currency and preserves destination ordering.
  public mutating func changeSource(_ code: String) {
    guard CurrencyCatalog.codes.contains(code), code != source else { return }
    let oldSource = source
    let updated = manualDestinations.map { $0 == code ? oldSource : $0 }
    source = code
    setDestinations(updated)
  }
}

extension ConverterState {
  /// Moves existing destinations before an anchor, preserving concurrently added currencies.
  /// A missing anchor places the moved currencies at the end.
  public mutating func moveDestinations(_ codes: [String], before anchor: String?) {
    let moving = codes.filter { manualDestinations.contains($0) }
    var remaining = manualDestinations.filter { !moving.contains($0) }
    let index = anchor.flatMap { remaining.firstIndex(of: $0) } ?? remaining.endIndex
    remaining.insert(contentsOf: moving, at: index)
    setDestinations(remaining)
  }
}
