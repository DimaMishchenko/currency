import ExchangeRates
import Foundation

/// App-facing descriptions of recoverable rate-service conditions.
public enum RateMessages {
  /// Returns a localized-app warning for a rate refresh, or nil on success.
  public static func refresh(_ warning: RefreshWarning?) -> LocalizedStringResource? {
    switch warning {
    case .dailyRatesUnavailable: .Support.dailyUnavailable
    case .partialCryptoFallback: .Support.cryptoFallback
    case nil: nil
    }
  }

  /// Returns the app's explanation of a history result, or nil on success.
  public static func history(_ issue: HistoryIssue?) -> LocalizedStringResource? {
    switch issue {
    case .unsupportedPair: .Support.historyUnsupported
    case .unavailable: .Support.historyUnavailable
    case .usingCachedSeries: .Support.historyCached
    case .cacheWriteFailed: .Support.historySaveFailed
    case nil: nil
    }
  }

  /// Formats structured provider context using the app's catalog and the requested locale.
  public static func providerDescription(_ source: RateSource, locale: Locale = .current) -> String
  {
    let provider: String
    switch source.provider {
    case .ecb: provider = "ECB"
    case .frankfurter: provider = "Frankfurter"
    case .fawaz: provider = "Fawaz"
    case .coinbase: provider = "Coinbase"
    case .custom(let name): provider = name
    }
    var resource: LocalizedStringResource
    switch source.observation {
    case .unspecified, .trade: return provider
    case .exchangeRate: resource = .Support.retrievedRates(provider)
    case .dailyRate: resource = .Support.dailyRates(provider)
    case .dailyReference: resource = .Support.dailyReference(provider)
    case .monthlyReference: resource = .Support.monthlyReference(provider)
    case .dailyClose: resource = .Support.dailyCloses(provider)
    case .monthlyLastClose: resource = .Support.monthlyLastClose(provider)
    }
    resource.locale = locale
    let description = String(localized: resource)
    guard let timeZone = source.timeZone else { return description }
    var withZone = LocalizedStringResource.Support.sourceWithTimeZone(
      description, timeZone.identifier)
    withZone.locale = locale
    return String(localized: withZone)
  }
}
