import Foundation

/// A provider identity, independent of localized presentation text.
public enum RateProviderID: Codable, Sendable, Equatable {
  /// European Central Bank.
  case ecb
  /// Frankfurter reference-rate API.
  case frankfurter
  /// Fawaz daily exchange-rate feed.
  case fawaz
  /// Coinbase market data.
  case coinbase
  /// A consumer-supplied provider identity or display name.
  case custom(String)
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
  /// A historical monthly reference rate.
  case monthlyReference
  /// A completed daily closing price.
  case dailyClose
  /// The last available daily close in each month.
  case monthlyLastClose
}

/// Structured provenance that consumers can format or localize without parsing text.
public struct RateSource: Codable, Sendable, Equatable {
  /// The provider responsible for the observation.
  public let provider: RateProviderID
  /// The observation's sampling or aggregation semantics.
  public let observation: RateObservation
  /// The time zone used for date buckets, when specified by the provider.
  public let timeZone: TimeZone?

  /// Creates provider context without prescribing its display wording.
  public init(
    provider: RateProviderID, observation: RateObservation = .unspecified, timeZone: TimeZone? = nil
  ) {
    self.provider = provider
    self.observation = observation
    self.timeZone = timeZone
  }

  private enum CodingKeys: String, CodingKey { case provider, observation, timeZone }

  /// Decodes structured provenance or migrates the former source-string cache format.
  public init(from decoder: any Decoder) throws {
    if let legacy = try? decoder.singleValueContainer().decode(String.self) {
      switch legacy {
      case "ECB": self.init(provider: .ecb, observation: .dailyRate)
      case "Frankfurter": self.init(provider: .frankfurter, observation: .dailyRate)
      case "Fawaz · daily": self.init(provider: .fawaz, observation: .dailyRate)
      case "Coinbase": self.init(provider: .coinbase, observation: .trade)
      case "Coinbase · daily closes · UTC":
        self.init(provider: .coinbase, observation: .dailyClose, timeZone: .gmt)
      case "Coinbase · monthly last available close · UTC":
        self.init(provider: .coinbase, observation: .monthlyLastClose, timeZone: .gmt)
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
      timeZone: try values.decodeIfPresent(TimeZone.self, forKey: .timeZone))
  }
}
