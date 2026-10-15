import ExchangeRates
import Foundation

/// Shared provider configuration for the app, extensions and independent Watch app.
public enum CurrencyRateConfiguration {
  /// Provider capabilities selected at each executable composition root.
  public static let policy: RateProviderPolicy = .intradayEnhanced

  /// Foreground polling respects the available provider update frequency.
  public static let foregroundRefreshInterval: TimeInterval = 60

  /// Requested widget refresh cadence; the system decides actual execution times.
  public static var widgetRefreshInterval: TimeInterval {
    policy.refreshInterval
  }
}
