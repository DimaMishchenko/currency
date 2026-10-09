import ExchangeRates
import Foundation

/// Shared build configuration for the app, extensions and independent Watch app.
public enum CurrencyRateConfiguration {
  /// Set CURRENCY_DISABLE_COINBASE when building to use only daily Fawaz data.
  public static let coinbaseEnabled: Bool = {
    #if CURRENCY_DISABLE_COINBASE
      false
    #else
      true
    #endif
  }()

  /// Provider capabilities selected once at each executable composition root.
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
