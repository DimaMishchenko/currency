import Foundation

extension Currency {
  /// Returns the display precision for a currency code.
  public static func fractionDigits(_ code: String) -> Int {
    crypto.contains(code)
      ? 8
      : ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"].contains(code)
        ? 3
        : [
          "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV", "XAF",
          "XOF", "XPF", "ISK"
        ]
        .contains(code) ? 0 : 2
  }
  /// Returns the flag or symbol associated with a currency code.
  public static func flag(_ code: String) -> String {
    let overrides = [
      "EUR": "🇪🇺", "ANG": "🇨🇼", "XCG": "🇨🇼", "XAF": "🌍", "XOF": "🌍", "XCD": "🌎", "XPF": "🇵🇫",
      "XDR": "🌐", "XAU": "🥇", "XAG": "🥈", "XPT": "⚪️", "XPD": "⚪️", "CNH": "🇨🇳"
    ]
    if let flag = overrides[code] { return flag }
    if crypto.contains(code) { return "🪙" }
    let region = String(code.prefix(2))
    if Locale.Region.isoRegions.contains(where: { $0.identifier == region }) {
      return String(
        String.UnicodeScalarView(
          region.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
    }
    return legacyFlag(code)
  }
  private static func legacyFlag(_ code: String) -> String {
    [
      "EUR": "🇪🇺", "USD": "🇺🇸", "GBP": "🇬🇧", "CZK": "🇨🇿", "CHF": "🇨🇭", "JPY": "🇯🇵", "CAD": "🇨🇦",
      "AUD": "🇦🇺", "PLN": "🇵🇱", "SEK": "🇸🇪", "NOK": "🇳🇴", "DKK": "🇩🇰", "HUF": "🇭🇺", "RON": "🇷🇴",
      "NZD": "🇳🇿", "CNY": "🇨🇳", "HKD": "🇭🇰", "SGD": "🇸🇬", "INR": "🇮🇳", "KRW": "🇰🇷", "MXN": "🇲🇽",
      "BRL": "🇧🇷", "ZAR": "🇿🇦", "TRY": "🇹🇷", "THB": "🇹🇭", "IDR": "🇮🇩", "ILS": "🇮🇱", "MYR": "🇲🇾",
      "PHP": "🇵🇭", "ISK": "🇮🇸"
    ][code] ?? "🪙"
  }
}

extension InputState {
  /// The normalized ordered destination currencies.
  public var destinations: [String] {
    var seen = Set<String>()
    return (savedTargets ?? [to, "GBP", "CZK", "JPY", "CHF", "BTC"])
      .filter {
        $0 != from && Currency.codes.contains($0) && seen.insert($0).inserted
      }
  }
  /// Replaces and normalizes the destination currencies.
  public mutating func setDestinations(_ codes: [String]) {
    savedTargets = codes
    savedTargets = destinations
    to = destinations.first ?? from
  }
  /// Promotes a destination to the source while preserving its converted value.
  public mutating func useAsBase(_ code: String, book: RateBook) {
    guard code != from, Currency.codes.contains(code),
      let converted = book.convert(decimal, from: from, to: code)
    else { return }
    var value = converted
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, Currency.fractionDigits(code), .plain)
    let oldSource = from
    let updated = destinations.map { $0 == code ? oldSource : $0 }
    from = code
    amount = NSDecimalNumber(decimal: rounded).stringValue
    setDestinations(updated)
    editedAt = Date()
  }
  /// Changes the source currency and preserves destination ordering.
  public mutating func changeSource(_ code: String) {
    guard Currency.codes.contains(code), code != from else { return }
    let oldSource = from
    let updated = destinations.map { $0 == code ? oldSource : $0 }
    from = code
    setDestinations(updated)
  }
}
