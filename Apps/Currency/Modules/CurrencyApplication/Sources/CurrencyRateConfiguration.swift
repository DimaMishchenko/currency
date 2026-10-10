import ExchangeRates
import Foundation

/// Shared provider configuration for the app, extensions and independent Watch app.
public enum CurrencyRateConfiguration {
  /// Enables Coinbase current crypto quotes and supported 24-hour charts.
  public static let coinbaseEnabled = true

  /// Provider capabilities selected at each executable composition root.
  public static var policy: RateProviderPolicy {
    coinbaseEnabled ? .coinbaseEnhanced : .daily
  }

  /// Foreground polling respects the available provider update frequency.
  public static var foregroundRefreshInterval: TimeInterval {
    coinbaseEnabled ? 60 : 21_600
  }

  /// Requested widget refresh cadence; the system decides actual execution times.
  public static var widgetRefreshInterval: TimeInterval {
    policy.refreshInterval
  }
}
