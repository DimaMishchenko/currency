import Foundation

/// The mass unit used for precious-metal input and conversion results.
public enum MetalUnit: String, Codable, CaseIterable, Sendable {
  case troyOunce, gram, kilogram

  /// The compact unit label used beside precious-metal amounts.
  public var symbol: String {
    switch self {
    case .troyOunce: "troy oz"
    case .gram: "g"
    case .kilogram: "kg"
    }
  }

  /// Exact mass of one selected unit, in grams.
  public var gramsPerUnit: Decimal {
    switch self {
    case .troyOunce: Decimal(311_034_768) / 10_000_000
    case .gram: 1
    case .kilogram: 1000
    }
  }

  /// Changes the mass representation without changing its physical quantity.
  public func converted(_ amount: Decimal, to unit: MetalUnit) -> Decimal {
    if self == unit { return amount }
    return amount * gramsPerUnit / unit.gramsPerUnit
  }

  /// Multiplier applied to a canonical troy-ounce cross rate for the selected metal unit.
  public func rateFactor(from: String, to: String) -> Decimal {
    let sourceIsMetal = CurrencyCode(rawValue: from)?.isMetal == true
    let targetIsMetal = CurrencyCode(rawValue: to)?.isMetal == true
    if sourceIsMetal == targetIsMetal { return 1 }
    return sourceIsMetal
      ? gramsPerUnit / MetalUnit.troyOunce.gramsPerUnit
      : MetalUnit.troyOunce.gramsPerUnit / gramsPerUnit
  }
}
