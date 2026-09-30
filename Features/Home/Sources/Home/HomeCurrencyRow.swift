import Foundation

/// Resolved conversion and editing eligibility for a workspace selection.
public struct HomeCurrencyRow: Sendable {
  /// Converted amount, absent when the current rates cannot resolve the currency.
  public let amount: Decimal?
  /// Whether the identified selection can receive amount edits.
  public let isEditable: Bool
}
