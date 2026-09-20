import ExchangeRates
import Foundation

/// Curated everyday banknotes and explicitly labeled fallback reference amounts.
public enum WidgetPresets {
  /// Precious metals whose provider units are troy ounces.
  public static let metals: Set<String> = ["XAU", "XAG", "XPT", "XPD"]
  /// ISO precious-metal quotes are troy ounces; one troy ounce is exactly this many grams.
  public static let gramsPerTroyOunce = Decimal(string: "31.1034768") ?? 31
  /// Three common banknote denominations for each supported cash currency.
  public static let banknotes: [String: [Decimal]] = [
    "EUR": [10, 20, 50], "USD": [5, 20, 100], "GBP": [5, 10, 20],
    "CZK": [100, 500, 1000], "CHF": [10, 50, 100], "JPY": [1000, 5000, 10000],
    "CAD": [5, 20, 50], "AUD": [5, 20, 50], "PLN": [10, 50, 100],
    "UAH": [100, 500, 1000]
  ]
  /// Whether the asset is eligible for the cash and metal reference widget.
  public static func allows(_ code: String) -> Bool {
    CurrencyCatalog.codes.contains(code) && !CurrencyCatalog.crypto.contains(code) && code != "XDR"
  }

  /// Returns grams for metals, curated notes for known fiat, or generic reference amounts.
  public static func amounts(_ code: String) -> [Decimal] {
    metals.contains(code) ? [1, 10, 1000] : banknotes[code] ?? [1, 10, 100]
  }

  /// Whether the presets describe actual banknotes.
  public static func isBanknote(_ code: String) -> Bool { banknotes[code] != nil }
  /// Converts source grams to quoted ounces and target ounces back to grams.
  public static func convert(
    _ amount: Decimal, from: String, to: String, snapshot: RateSnapshot
  ) -> Decimal? {
    guard !amount.isNaN else { return nil }
    if from == to { return amount }
    let sourceAmount = metals.contains(from) ? amount / gramsPerTroyOunce : amount
    guard let result = snapshot.convert(sourceAmount, from: from, to: to) else { return nil }
    return metals.contains(to) ? result * gramsPerTroyOunce : result
  }
}
