import Foundation

/// Currency precision shared by editing, conversion and presentation.
public enum CurrencyPrecision {
  /// Returns the supported fractional precision for a currency code.
  public static func fractionDigits(_ code: String) -> Int {
    guard let currency = CurrencyCode(rawValue: code) else { return 2 }
    if currency.isCryptocurrency { return 8 }
    switch currency {
    case .bhd, .iqd, .jod, .kwd, .lyd, .omr, .tnd: return 3
    case .bif, .clp, .djf, .gnf, .jpy, .kmf, .krw, .pyg, .rwf, .ugx, .vnd, .vuv,
      .xaf, .xof, .xpf, .isk:
      return 0
    default: return 2
    }
  }
}
