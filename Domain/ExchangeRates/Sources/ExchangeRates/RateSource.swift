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

  private enum CodingKeys: String, CodingKey {
    case ecb, frankfurter, fawaz, coinMetrics, custom, coinbase
  }
  private enum ValueKeys: String, CodingKey { case _0 }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard values.allKeys.count == 1, let key = values.allKeys.first else {
      throw RateError.invalidData
    }
    switch key {
    case .ecb: self = .ecb
    case .frankfurter: self = .frankfurter
    case .fawaz: self = .fawaz
    case .coinMetrics: self = .coinMetrics
    case .coinbase: self = .custom("Coinbase")
    case .custom:
      self = .custom(
        try values.nestedContainer(keyedBy: ValueKeys.self, forKey: key)
          .decode(String.self, forKey: ._0))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    let key: CodingKeys
    switch self {
    case .ecb: key = .ecb
    case .frankfurter: key = .frankfurter
    case .fawaz: key = .fawaz
    case .coinMetrics: key = .coinMetrics
    case .custom(let name):
      var nested = values.nestedContainer(keyedBy: ValueKeys.self, forKey: .custom)
      try nested.encode(name, forKey: ._0)
      return
    }
    _ = values.nestedContainer(keyedBy: ValueKeys.self, forKey: key)
  }

}

/// How a provider's observation was sampled or aggregated.
public enum RateObservation: String, Codable, Sendable {
  /// The provider supplies no observation semantics.
  case unspecified
  /// A daily current-rate publication.
  case dailyRate
  /// A current exchange rate without a provider observation timestamp.
  case exchangeRate
  /// An individual market trade.
  case trade
  /// A historical daily reference rate.
  case dailyReference
  /// A minute reference-rate observation.
  case minuteReference
  /// A historical monthly reference rate.
  case monthlyReference
  /// A completed hourly closing price.
  case hourlyClose
  /// A completed daily closing price.
  case dailyClose
  /// The last available daily close in each month.
  case monthlyLastClose
}

/// Daily FX input used to normalize reference rates.
public struct RateConversion: Codable, Sendable, Equatable {
  /// The daily FX provider.
  public let provider: RateProviderID
  /// Publication date of the FX observation.
  public let published: String
  /// Quote currency units per one base currency unit.
  public let value: Decimal
  public let base: String
  public let quote: String

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
  /// A distinct sampling interval used for a newer endpoint in a historical series.
  public let latestObservation: RateObservation?
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
    latestObservation: RateObservation? = nil,
    conversion: RateConversion? = nil, contributingProviders: [RateProviderID]? = nil
  ) {
    self.provider = provider
    self.observation = observation
    self.latestObservation = latestObservation
    self.timeZone = timeZone
    self.conversion = conversion
    self.contributingProviders = contributingProviders
  }

  private enum CodingKeys: String, CodingKey {
    case provider, observation, timeZone, latestObservation, conversion, contributingProviders
  }

  /// Decodes structured provenance or migrates the former source-string cache format.
  public init(from decoder: any Decoder) throws {
    if let legacy = try? decoder.singleValueContainer().decode(String.self) {
      switch legacy {
      case "ECB": self.init(provider: .ecb, observation: .dailyRate)
      case "Frankfurter": self.init(provider: .frankfurter, observation: .dailyRate)
      case "Fawaz · daily": self.init(provider: .fawaz, observation: .dailyRate)
      case "Coinbase": self.init(provider: .custom("Coinbase"), observation: .trade)
      case "Coinbase · daily closes · UTC":
        self.init(provider: .custom("Coinbase"), observation: .dailyClose, timeZone: .gmt)
      case "Coinbase · monthly last available close · UTC":
        self.init(provider: .custom("Coinbase"), observation: .monthlyLastClose, timeZone: .gmt)
      case "Frankfurter · daily reference rates":
        self.init(provider: .frankfurter, observation: .dailyReference)
      case "Frankfurter · monthly reference rates":
        self.init(provider: .frankfurter, observation: .monthlyReference)
      default: self.init(provider: .custom(legacy))
      }
      return
    }
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      provider: try values.decode(RateProviderID.self, forKey: .provider),
      observation: try values.decode(RateObservation.self, forKey: .observation),
      timeZone: try values.decodeIfPresent(TimeZone.self, forKey: .timeZone),
      latestObservation: try values.decodeIfPresent(
        RateObservation.self, forKey: .latestObservation),
      conversion: try values.decodeIfPresent(RateConversion.self, forKey: .conversion),
      contributingProviders: try values.decodeIfPresent(
        [RateProviderID].self, forKey: .contributingProviders))
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
        latestObservation: source.latestObservation, conversion: selected,
        contributingProviders: source.contributingProviders),
      observedAt: observedAt, retrievedAt: retrievedAt, cachedAt: cachedAt)
  }
}
