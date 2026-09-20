import Conversion
import ExchangeRates
import Foundation
import LocalCurrency

/// Widget configuration policies over the shared currency-selection rules.
public enum WidgetSelection {
  /// Canonical identifier for dynamic Local selection.
  public static let localID = CurrencySelection.localID
  /// Whether a selection retains Local intent.
  public static func isLocal(_ code: String) -> Bool { CurrencySelection.isLocal(code) }
  /// The currency of a resolved selection.
  public static func currency(_ code: String) -> String { CurrencySelection.currency(code) }
  /// Normalizes configured selections while preserving their order.
  public static func normalize(_ codes: [String], allowsLocal: Bool = false) -> [String] {
    CurrencySelection.normalize(codes, allowsLocal: allowsLocal)
  }
  /// Resolved app currencies for an installed widget.
  public static func appCurrencies(_ input: ConverterState) -> [String] {
    CurrencySelection.appCurrencies(input)
  }
  /// Canonical app selections, preserving Local intent.
  public static func appConfiguration(_ input: ConverterState) -> [String] {
    CurrencySelection.appConfiguration(input)
  }
  /// Resolves only list ownership; amounts and active input remain widget-specific.
  public static func calculator(
    app: ConverterState, custom: [String]?, usesCustom: Bool, includeLocal: Bool
  ) -> [String] {
    if usesCustom { return normalize(custom ?? [], allowsLocal: true) }
    return normalize(appConfiguration(app) + (includeLocal ? [localID] : []), allowsLocal: true)
  }

  /// Places the board base before its unique target currencies.
  public static func board(base: String, targets: [String]) -> [String] {
    normalize([base] + targets, allowsLocal: true)
  }
}
