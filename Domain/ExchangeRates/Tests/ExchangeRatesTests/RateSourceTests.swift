import ExchangeRates
import Foundation
import Testing

@Suite struct RateSourceTests {
  @Test func conversionMetadataRoundTripsAndPlainSourceHasNoAssumedFX() throws {
    let source = RateSource(
      provider: .coinMetrics, observation: .minuteReference,
      conversion: .init(
        provider: .fawaz, published: "2026-01-02", value: 1.2, base: "EUR", quote: "USD"),
      contributingProviders: [.fawaz, .coinMetrics])
    let restored = try JSONDecoder().decode(RateSource.self, from: JSONEncoder().encode(source))
    #expect(restored == source)
    let plain = try JSONDecoder()
      .decode(
        RateSource.self,
        from: Data(#"{"provider":{"fawaz":{}},"observation":"dailyReference"}"#.utf8))
    #expect(plain.conversion == nil)
    #expect(plain.contributingProviders == nil)
  }

  @Test func customProviderRoundTripsWithoutInterpretingDisplayText() throws {
    let source = RateSource(provider: .custom("My reference feed"), observation: .dailyReference)
    #expect(try JSONDecoder().decode(RateSource.self, from: JSONEncoder().encode(source)) == source)

  }
}
