import ExchangeRates
import Foundation

/// Localized names, symbols, and amount formatting for Currency screens and widgets.
public enum CurrencyDisplay {
  /// Returns a localized display name for a currency code.
  public static func name(_ code: String, locale: Locale = .current) -> String {
    guard let currency = CurrencyCode(rawValue: code) else { return code }
    let name = currency.assetName ?? locale.localizedString(forCurrencyCode: code) ?? code
    return name.prefix(1).uppercased(with: locale) + name.dropFirst()
  }

  /// Formats a currency value using the currency's supported precision.
  public static func format(
    _ value: Decimal?, code: String, locale: Locale = .current, metalUnit: MetalUnit = .troyOunce
  ) -> String {
    guard let value, !value.isNaN else { return "—" }
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = fractionDigits(code, metalUnit: metalUnit)
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
  }
}

extension CurrencyDisplay {
  /// Returns the display precision for a currency code.
  public static func fractionDigits(_ code: String, metalUnit: MetalUnit = .troyOunce) -> Int {
    CurrencyPrecision.fractionDigits(code, metalUnit: metalUnit)
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
    case .btc: String(localized: "Bitcoin", table: "Support", bundle: .module)
    case .eth: String(localized: "Ethereum", table: "Support", bundle: .module)
    case .sol: String(localized: "Solana", table: "Support", bundle: .module)
    case .doge: String(localized: "Dogecoin", table: "Support", bundle: .module)
    case .ltc: String(localized: "Litecoin", table: "Support", bundle: .module)
    case .usdc: String(localized: "USD Coin", table: "Support", bundle: .module)
    case .usdt: String(localized: "Tether", table: "Support", bundle: .module)
    case .xrp: String(localized: "XRP", table: "Support", bundle: .module)
    case .ada: String(localized: "Cardano", table: "Support", bundle: .module)
    case .avax: String(localized: "Avalanche", table: "Support", bundle: .module)
    case .link: String(localized: "Chainlink", table: "Support", bundle: .module)
    case .dot: String(localized: "Polkadot", table: "Support", bundle: .module)
    case .bch: String(localized: "Bitcoin Cash", table: "Support", bundle: .module)
    case .xlm: String(localized: "Stellar", table: "Support", bundle: .module)
    case .atom: String(localized: "Cosmos", table: "Support", bundle: .module)
    case .uni: String(localized: "Uniswap", table: "Support", bundle: .module)
    case .etc: String(localized: "Ethereum Classic", table: "Support", bundle: .module)
    case .fil: String(localized: "Filecoin", table: "Support", bundle: .module)
    case .aave: String(localized: "Aave", table: "Support", bundle: .module)
    case .algo: String(localized: "Algorand", table: "Support", bundle: .module)
    case .shib: String(localized: "Shiba Inu", table: "Support", bundle: .module)
    case .icp: String(localized: "Internet Computer", table: "Support", bundle: .module)
    default: nil
    }
  }
}

extension CurrencyDisplay {
  /// Groups the integer and localizes editable digits without losing fractional precision or zeros.
  /// A separator without a following digit stays hidden until the fraction begins.
  public static func inputAmount(_ amount: String, locale: Locale = .current) -> String {
    let visibleAmount = amount.hasSuffix(".") ? String(amount.dropLast()) : amount
    let parts = visibleAmount.split(separator: ".", omittingEmptySubsequences: false)
    let integer =
      Decimal(string: String(parts.first ?? "0"), locale: Locale(identifier: "en_US_POSIX")) ?? 0
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    formatter.usesGroupingSeparator = true
    let grouped = formatter.string(from: NSDecimalNumber(decimal: integer)) ?? "0"
    guard parts.count > 1 else { return grouped }
    let fraction = keypadLabel(String(parts[1]), locale: locale)
    return grouped + (locale.decimalSeparator ?? ".") + fraction
  }

  /// Localizes keypad symbols verbatim, keeping multi-zero keys and a standalone decimal separator.
  public static func keypadLabel(_ key: String, locale: Locale = .current) -> String {
    key.map { character in
      if character == "." { return locale.decimalSeparator ?? "." }
      return character.wholeNumberValue.map { $0.formatted(.number.locale(locale)) }
        ?? String(character)
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
      .map { rate in
        let source = presentationSource(rate.source, snapshot: snapshot, from: from, to: to)
        let detail =
          RateMessages.providerDescription(source, locale: locale) + " · "
          + publicationDate(rate.published, locale: locale)
        return [detail, RateMessages.conversionDescription(source, locale: locale)]
          .compactMap { $0 }.joined(separator: "\n")
      }
    return Set(descriptions).sorted().joined(separator: " / ")
  }

  /// Describes only the FX input that remains in the requested conversion.
  public static func presentationSource(
    _ source: RateSource, snapshot: RateSnapshot, from: String, to: String
  ) -> RateSource {
    guard source.provider == .coinMetrics, source.conversion != nil else { return source }
    guard from == to || normalizationCancels(snapshot, from: from, to: to) else { return source }
    return RateSource(
      provider: source.provider, observation: source.observation, timeZone: source.timeZone,
      contributingProviders: source.contributingProviders)
  }

  /// Presents a quote in the context of the selected base and destination currencies.
  public static func quoteSource(
    _ snapshot: RateSnapshot, code: String, base: String, destinations: [String]
  ) -> RateSource? {
    guard let source = snapshot.quotes[code]?.source else { return nil }
    let comparisons = code == base ? destinations.filter { $0 != base } : [code]
    let sources = comparisons.map {
      presentationSource(source, snapshot: snapshot, from: base, to: $0)
    }
    return sources.first { $0.conversion != nil } ?? sources.first
      ?? presentationSource(source, snapshot: snapshot, from: base, to: base)
  }

  private static func normalizationCancels(
    _ snapshot: RateSnapshot, from: String, to: String
  ) -> Bool {
    guard let first = snapshot.quotes[from], let second = snapshot.quotes[to] else { return false }
    if first.source.provider == .coinMetrics, second.source.provider == .coinMetrics,
      let anchor = first.source.conversion, anchor.base == "EUR", anchor.quote == "USD",
      anchor.value > 0, !anchor.value.isNaN, anchor == second.source.conversion
    {
      return true
    }
    let crypto: ExchangeRate
    let usd: ExchangeRate
    if from == "USD" {
      crypto = second; usd = first
    } else if to == "USD" {
      crypto = first; usd = second
    } else {
      return false
    }
    guard crypto.source.provider == .coinMetrics, let anchor = crypto.source.conversion else {
      return false
    }
    return anchor.base == "EUR" && anchor.quote == "USD" && anchor.value > 0
      && !anchor.value.isNaN && anchor.value == usd.value
      && anchor.provider == usd.source.provider && anchor.published == usd.published
  }

}
