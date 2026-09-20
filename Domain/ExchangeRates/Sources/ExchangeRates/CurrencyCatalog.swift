/// The bundled currency selection catalog used by the built-in providers.
public enum CurrencyCatalog {
  /// Supported cryptocurrency codes, derived from the typed catalog.
  public static let crypto = Set(CurrencyCode.allCases.filter(\.isCryptocurrency).map(\.rawValue))
  /// Supported currency codes in the catalog's display order.
  public static let codes = CurrencyCode.allCases.map(\.rawValue)
}
