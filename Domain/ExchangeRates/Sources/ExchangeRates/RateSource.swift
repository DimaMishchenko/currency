import Foundation

/// A provider identity, independent of localized presentation text.
public enum RateProviderID: Codable, Sendable, Equatable {
  /// European Central Bank.
  case ecb
  /// Frankfurter reference-rate API.
  case frankfurter
  /// Fawaz daily exchange-rate feed.
  case fawaz
  /// Coin Metrics reference rates.
  case coinMetrics
  /// A consumer-supplied provider identity or display name.
  case custom(String)

}

/// How a provider's observation was sampled or aggregated.
public enum RateObservation: String, Codable, Sendable {
  /// The provider supplies no observation semantics.
  case unspecified
  /// A daily current-rate publication.
  case dailyRate
  /// A historical daily reference rate.
  case dailyReference
  /// A minute reference-rate observation.
  case minuteReference
  /// A historical monthly reference rate.
  case monthlyReference
}

/// Daily FX input used to normalize reference rates.
public struct RateConversion: Codable, Sendable, Equatable {
  /// The daily FX provider.
  public let provider: RateProviderID
  /// Publication date of the FX observation.
  public let published: String
  /// Quote currency units per one base currency unit.
  public let value: Decimal
  /// Currency being converted from.
  public let base: String
  /// Currency being converted to.
  public let quote: String

  /// Records the exact daily input used for an approximate conversion.
  public init(
    provider: RateProviderID, published: String, value: Decimal, base: String, quote: String
  ) {
    self.provider = provider
    self.published = published
    self.value = value
    self.base = base
    self.quote = quote
  }
}

/// Structured provenance that consumers can format or localize without parsing text.
public struct RateSource: Codable, Sendable, Equatable {
  /// The provider responsible for the observation.
  public let provider: RateProviderID
  /// The observation's sampling or aggregation semantics.
  public let observation: RateObservation
  /// The time zone used for date buckets, when specified by the provider.
  public let timeZone: TimeZone?

  /// The daily FX approximation used to convert market observations, when applicable.
  public let conversion: RateConversion?
  /// Additional providers represented in a stitched historical series.
  public let contributingProviders: [RateProviderID]?

  /// Creates provider context without prescribing its display wording.
  public init(
    provider: RateProviderID, observation: RateObservation = .unspecified,
    timeZone: TimeZone? = nil,
    conversion: RateConversion? = nil, contributingProviders: [RateProviderID]? = nil
  ) {
    self.provider = provider
    self.observation = observation
    self.timeZone = timeZone
    self.conversion = conversion
    self.contributingProviders = contributingProviders
  }

}

extension ExchangeRate {
  func alignedToDailyUSD(_ usd: ExchangeRate?) -> ExchangeRate? {
    guard source.provider == .coinMetrics, let conversion = source.conversion else { return self }
    guard conversion.base == "EUR", conversion.quote == "USD",
      conversion.value > 0, !conversion.value.isNaN,
      let usd, usd.value > 0, !usd.value.isNaN, !usd.isLive
    else { return nil }
    let selected = RateConversion(
      provider: usd.source.provider, published: usd.published, value: usd.value,
      base: "EUR", quote: "USD")
    if selected == conversion { return self }
    let aligned = value * usd.value / conversion.value
    guard aligned > 0, !aligned.isNaN else { return nil }
    return ExchangeRate(
      aligned, published: published,
      source: RateSource(
        provider: source.provider, observation: source.observation, timeZone: source.timeZone,
        conversion: selected,
        contributingProviders: source.contributingProviders),
      observedAt: observedAt, retrievedAt: retrievedAt, cachedAt: cachedAt)
  }
}
