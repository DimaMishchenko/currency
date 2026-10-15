import Foundation

/// Shared refresh cadence for the app, extensions and independent Watch app.
public enum CurrencyRateConfiguration {
  /// Foreground polling respects the available provider update frequency.
  public static let foregroundRefreshInterval: TimeInterval = 60

  /// Requested widget refresh cadence; the system decides actual execution times.
  public static let widgetRefreshInterval: TimeInterval = 1800
}
