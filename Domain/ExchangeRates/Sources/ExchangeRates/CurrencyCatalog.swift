import Foundation

/// The bundled currency selection catalog used by the built-in providers.
public enum CurrencyCatalog {
  /// Supported cryptocurrency codes, derived from the typed catalog.
  public static let crypto = Set(CurrencyCode.allCases.filter(\.isCryptocurrency).map(\.rawValue))
  /// Supported currency codes in the catalog's stable provider order.
  public static let codes = CurrencyCode.allCases.map(\.rawValue)
  /// Precious metals available separately from fiat currencies.
  public static let metals: Set<String> = ["XAU", "XAG", "XPT", "XPD"]
  /// A product-curated shortlist of major fiat currencies, independent of location.
  public static let popularFiat = ["USD", "EUR", "JPY", "GBP", "CHF", "CAD", "AUD", "CNY"]
  /// A product-curated shortlist of cryptocurrencies, independent of market ranking.
  public static let popularCrypto = ["BTC", "ETH", "SOL", "USDC", "USDT"]

  /// Fiat currencies in alphabetical code order, without the curated shortlist or metals.
  public static let otherFiat =
    codes.filter {
      !crypto.contains($0) && !metals.contains($0) && !popularFiat.contains($0)
    }
    .sorted()
  /// Cryptocurrencies in alphabetical code order, without the curated shortlist.
  public static let otherCrypto = crypto.filter { !popularCrypto.contains($0) }.sorted()

  /// Returns a canonical market name for supported crypto assets, independent of locale.
  public static func assetName(_ code: String) -> String? {
    guard let currency = CurrencyCode(rawValue: code) else { return nil }
    return switch currency {
    case .btc: "Bitcoin"
    case .eth: "Ethereum"
    case .sol: "Solana"
    case .doge: "Dogecoin"
    case .ltc: "Litecoin"
    case .usdc: "USD Coin"
    case .usdt: "Tether"
    case .xrp: "XRP"
    case .ada: "Cardano"
    case .avax: "Avalanche"
    case .link: "Chainlink"
    case .dot: "Polkadot"
    case .bch: "Bitcoin Cash"
    case .xlm: "Stellar"
    case .atom: "Cosmos"
    case .uni: "Uniswap"
    case .etc: "Ethereum Classic"
    case .fil: "Filecoin"
    case .aave: "Aave"
    case .algo: "Algorand"
    case .shib: "Shiba Inu"
    case .icp: "Internet Computer"
    default: nil
    }
  }

  /// Finds supported codes by exact code, code prefix, name prefix, then remaining matches.
  /// The caller supplies localized display names; ties use alphabetical code order.
  public static func search(
    _ query: String, allowedCodes: Set<String>? = nil, locale: Locale = .current,
    name: (String) -> String
  ) -> [String] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    guard !query.isEmpty else { return [] }
    return
      codes.compactMap { code -> (String, Int)? in
        guard allowedCodes?.contains(code) ?? true else { return nil }
        let normalizedCode = code.folding(options: .caseInsensitive, locale: locale)
        let normalizedName = name(code)
          .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        let rank: Int
        if normalizedCode == query {
          rank = 0
        } else if normalizedCode.hasPrefix(query) {
          rank = 1
        } else if normalizedName == query {
          rank = 2
        } else if normalizedName.hasPrefix(query) {
          rank = 3
        } else if normalizedCode.contains(query) || normalizedName.contains(query) {
          rank = 4
        } else {
          return nil
        }
        return (code, rank)
      }
      .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
      .map(\.0)
  }
}
