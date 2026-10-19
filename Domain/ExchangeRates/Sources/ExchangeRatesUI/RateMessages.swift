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
    case .intradayUnavailable: .Support.historyIntradayUnavailable
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
    case .coinMetrics: provider = "Coin Metrics"
    case .custom(let name): provider = name
    }
    let contributors = (source.contributingProviders ?? []).map(providerName)
    let names = ([provider] + contributors)
      .reduce(into: [String]()) {
        if !$0.contains($1) { $0.append($1) }
      }
      .joined(separator: " + ")
    var description = observationDescription(source.observation, provider: names, locale: locale)
    if source.conversion != nil {
      var approximate = LocalizedStringResource.Support.approximateSource(description)
      approximate.locale = locale
      description = String(localized: approximate)
    }
    guard let timeZone = source.timeZone else { return description }
    var withZone = LocalizedStringResource.Support.sourceWithTimeZone(
      description, timeZone.identifier)
    withZone.locale = locale
    return String(localized: withZone)
  }

  /// Describes the reference FX rate used to calculate a converted quote.
  public static func conversionDescription(
    _ source: RateSource, locale: Locale = .current
  ) -> String? {
    guard let conversion = source.conversion else { return nil }
    let value = NSDecimalNumber(decimal: conversion.value).description(withLocale: locale)
    var resource = LocalizedStringResource.Support.conversionReference(
      conversion.base, value, conversion.quote, providerName(conversion.provider),
      CurrencyDisplay.publicationDate(conversion.published, locale: locale))
    resource.locale = locale
    return String(localized: resource)
  }

  private static func providerName(_ provider: RateProviderID) -> String {
    switch provider {
    case .ecb: "ECB"
    case .frankfurter: "Frankfurter"
    case .fawaz: "Fawaz"
    case .coinMetrics: "Coin Metrics"
    case .custom(let name): name
    }
  }

  private static func observationDescription(
    _ observation: RateObservation, provider: String, locale: Locale
  ) -> String {
    var resource: LocalizedStringResource
    switch observation {
    case .unspecified: return provider
    case .dailyRate: resource = .Support.dailyRates(provider)
    case .minuteReference: resource = .Support.minuteReference(provider)
    case .hourlyReference: resource = .Support.hourlyReference(provider)
    case .dailyReference: resource = .Support.dailyReference(provider)
    case .monthlyReference: resource = .Support.monthlyReference(provider)
    }
    resource.locale = locale
    return String(localized: resource)
  }
}
