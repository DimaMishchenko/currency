import ExchangeRates
import Foundation
import Testing

@Suite struct RateSourceTests {
  @Test func legacyProvenanceDecodesIntoStructuredContext() throws {
    let source = try JSONDecoder()
      .decode(
        RateSource.self, from: Data(#""Coinbase · monthly last available close · UTC""#.utf8))
    #expect(source.provider == .custom("Coinbase"))
    #expect(source.observation == .monthlyLastClose)
    #expect(source.timeZone == .gmt)
    #expect(try JSONDecoder().decode(RateSource.self, from: JSONEncoder().encode(source)) == source)
  }

  @Test(arguments: [RateObservation.dailyClose, .monthlyLastClose, .unspecified])
  func mixedHistoryProvenanceRoundTripsWithoutRelabelingHistoricalPoints(
    observation: RateObservation
  ) throws {
    let source = RateSource(
      provider: .coinMetrics, observation: observation, timeZone: .gmt,
      latestObservation: .hourlyClose)
    let restored = try JSONDecoder().decode(RateSource.self, from: JSONEncoder().encode(source))
    #expect(restored == source)
    #expect(restored.observation == observation)
    #expect(restored.latestObservation == .hourlyClose)
    let original = RateSource(provider: .coinMetrics, observation: observation, timeZone: .gmt)
    let old = try JSONDecoder().decode(RateSource.self, from: JSONEncoder().encode(original))
    #expect(old.latestObservation == nil)
  }

  @Test func compositeConversionMetadataRoundTripsAndOldSourceHasNoAssumedFX() throws {
    let source = RateSource(
      provider: .coinMetrics, observation: .minuteReference,
      conversion: .init(
        provider: .fawaz, published: "2026-01-02", value: 1.2, base: "EUR", quote: "USD"),
      contributingProviders: [.fawaz, .coinMetrics])
    let restored = try JSONDecoder().decode(RateSource.self, from: JSONEncoder().encode(source))
    #expect(restored == source)
    let old = try JSONDecoder()
      .decode(
        RateSource.self,
        from: Data(#"{"provider":{"fawaz":{}},"observation":"dailyReference"}"#.utf8))
    #expect(old.conversion == nil)
    #expect(old.contributingProviders == nil)
  }

  @Test func customProviderRoundTripsWithoutInterpretingDisplayText() throws {
    let source = RateSource(provider: .custom("My reference feed"), observation: .dailyReference)
    #expect(try JSONDecoder().decode(RateSource.self, from: JSONEncoder().encode(source)) == source)
    let legacy = try JSONDecoder().decode(RateSource.self, from: Data(#""My reference feed""#.utf8))
    #expect(legacy.provider == source.provider)
    #expect(legacy.observation == .unspecified)
  }
}
