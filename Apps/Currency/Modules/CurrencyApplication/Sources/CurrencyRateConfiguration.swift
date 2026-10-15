import ExchangeRates
import Foundation

/// Shared provider configuration for the app, extensions and independent Watch app.
public enum CurrencyRateConfiguration {
  /// Enables Coin Metrics current crypto reference prices and 24-hour charts.
  public static let intradayEnabled = true

  /// Provider capabilities selected at each executable composition root.
  public static var policy: RateProviderPolicy {
    intradayEnabled ? .intradayEnhanced : .daily
  }

  /// Foreground polling respects the available provider update frequency.
  public static var foregroundRefreshInterval: TimeInterval {
    intradayEnabled ? 60 : 21_600
  }

  /// Requested widget refresh cadence; the system decides actual execution times.
  public static var widgetRefreshInterval: TimeInterval {
    policy.refreshInterval
  }
}
