import ExchangeRates
import Foundation

/// Localized names, symbols, and amount formatting for Currency screens and widgets.
public enum CurrencyDisplay {
  /// Returns a localized display name for a currency code.
  public static func name(_ code: String, locale: Locale = .current) -> String {
    guard let currency = CurrencyCode(rawValue: code) else { return code }
    return currency.assetName ?? locale.localizedString(forCurrencyCode: code) ?? code
  }
  /// Formats a currency value using the currency's supported precision.
  public static func format(_ value: Decimal?, code: String, locale: Locale = .current) -> String {
    guard let value, !value.isNaN else { return "—" }
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = fractionDigits(code)
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
  }
}

extension CurrencyDisplay {
  /// Returns the display precision for a currency code.
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
  /// Returns the flag or symbol associated with a currency code.
  public static func flag(_ code: String) -> String {
    guard let currency = CurrencyCode(rawValue: code) else { return "🪙" }
    switch currency {
    case .eur: return "🇪🇺"
    case .ang, .xcg: return "🇨🇼"
    case .xaf, .xof: return "🌍"
    case .xcd: return "🌎"
    case .xpf: return "🇵🇫"
    case .xdr: return "🌐"
    case .xau: return "🥇"
    case .xag: return "🥈"
    case .xpt, .xpd: return "⚪️"
    case .cnh: return "🇨🇳"
    default: break
    }
    if currency.isCryptocurrency { return "🪙" }
    let region = String(currency.rawValue.prefix(2))
    guard Locale.Region.isoRegions.contains(where: { $0.identifier == region }) else { return "🪙" }
    return String(
      String.UnicodeScalarView(
        region.unicodeScalars.compactMap {
          UnicodeScalar(127397 + $0.value)
        }))
  }
}

private extension CurrencyCode {
  var assetName: String? {
    switch self {
    case .btc: "Bitcoin"
    case .eth: "Ethereum"
    case .sol: "Solana"
    case .doge: "Dogecoin"
    case .ltc: "Litecoin"
    case .usdc: "USD Coin"
    case .usdt: "Tether"
    default: nil
    }
  }
}

extension CurrencyDisplay {
  /// Localizes editable digits and the decimal separator without losing trailing zeros.
  public static func inputAmount(_ amount: String, locale: Locale = .current) -> String {
    amount.map { character in
      if character == "." { return locale.decimalSeparator ?? "." }
      guard let digit = character.wholeNumberValue else { return String(character) }
      return digit.formatted(.number.locale(locale))
    }
    .joined()
  }

  /// Formats an ISO publication day using the requested locale; unknown values remain verbatim.
  public static func publicationDate(_ value: String, locale: Locale = .current) -> String {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone(secondsFromGMT: 0)
    parser.dateFormat = "yyyy-MM-dd"
    parser.isLenient = false
    guard let date = parser.date(from: value) else { return value }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateStyle = .medium
    return formatter.string(from: date)
  }

  /// Describes the distinct providers and publication days involved in a conversion.
  public static func details(
    _ snapshot: RateSnapshot, from: String, to: String, locale: Locale = .current
  ) -> String {
    let descriptions = [snapshot.quotes[from], snapshot.quotes[to]].compactMap { $0 }
      .map {
        RateMessages.providerDescription($0.source, locale: locale) + " · "
          + publicationDate($0.published, locale: locale)
      }
    return Set(descriptions).sorted().joined(separator: " / ")
  }
}
