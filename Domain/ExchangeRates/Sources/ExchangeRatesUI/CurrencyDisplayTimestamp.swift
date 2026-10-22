import Foundation

extension CurrencyDisplay {
  /// Formats an instant in the explicitly supplied display locale and time zone.
  public static func timestamp(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
    date.formatted(
      Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
  }

  /// Returns a localized zone name that covers both standard and daylight time.
  public static func timeZoneName(_ timeZone: TimeZone, locale: Locale) -> String {
    timeZone.localizedName(for: .generic, locale: locale) ?? timeZone.identifier
  }
}
