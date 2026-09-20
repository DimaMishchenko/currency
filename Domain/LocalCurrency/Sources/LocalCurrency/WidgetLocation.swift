import ExchangeRates
import Foundation

/// Coarse location only: no coordinates are persisted or sent to rate providers.
public struct WidgetLocation: Codable, Equatable, Sendable {
  /// The ISO country code returned by reverse geocoding.
  public let country: String
  /// The fiat currency associated with that country.
  public let currency: String
  /// The time of the explicit foreground location update.
  public let updatedAt: Date
  /// Creates a coarse cached location observation.
  public init(country: String, currency: String, updatedAt: Date = .now) {
    self.country = country
    self.currency = currency
    self.updatedAt = updatedAt
  }

  /// A stale supported observation remains usable after an authorized transient failure.
  public var isUsable: Bool {
    Self.isSupported(currency)
  }

  /// Whether this supported fiat observation is less than one day old.
  public func isFresh(now: Date = .now) -> Bool {
    now >= updatedAt && now.timeIntervalSince(updatedAt) < 86400
      && Self.isSupported(currency)
  }

  private static func isSupported(_ code: String) -> Bool {
    CurrencyCatalog.codes.contains(code) && !CurrencyCatalog.crypto.contains(code)
      && !["XAU", "XAG", "XPT", "XPD", "XDR"].contains(code)
  }

  /// Uses the country's current Foundation currency mapping, never the user's UI locale.
  public static func currency(for country: String) -> String? {
    guard Locale.Region.isoRegions.contains(where: { $0.identifier == country }) else { return nil }
    guard let code = Locale(identifier: "und_\(country)").currency?.identifier,
      isSupported(code)
    else { return nil }
    return code
  }
}

/// Persisted permission/lookup outcome, separate from the last supported observation.
public enum WidgetLocationStatus: String, Codable, Sendable {
  case notDetermined, denied, restricted, available, failed, removed

  /// Whether the outcome permits displaying the last supported observation.
  public var allowsCache: Bool { self == .available || self == .failed }
}
