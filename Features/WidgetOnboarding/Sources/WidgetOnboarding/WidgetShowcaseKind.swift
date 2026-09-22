import Foundation

/// Supported widget capabilities, independent of WidgetKit presentation families.
public enum WidgetShowcaseKind: String, CaseIterable, Identifiable, Sendable {
  case calculator, cash, pocket, history, mental, board, icon
  /// Stable identity for selection controls.
  public var id: Self { self }
  /// Ordered canonical currency codes used by this presentation.
  public var codes: [String] {
    switch self {
    case .calculator: ["EUR", "USD", "GBP", "JPY"]
    case .board:
      ["EUR", "USD", "GBP", "JPY", "CZK", "CHF", "CAD", "AUD", "SEK", "NOK", "PLN", "HUF"]
    case .cash: ["CZK", "EUR"]
    case .pocket: ["EUR", "USD"]
    case .mental, .history: ["EUR", "CZK"]
    case .icon: ["EUR", "USD"]
    }
  }
  /// Whether the capability supports keypad or preset interactions.
  public var interactive: Bool { self == .calculator || self == .cash }
}
