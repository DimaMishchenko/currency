import ExchangeRates
import ExchangeRatesUI
import Foundation
import Testing

@Suite struct RateTimestampTests {
  @Test(arguments: [
    ("en_GB", "1 Jul 2026 at 1:30", "30 Jun 2026 at 16:30"),
    ("de_DE", "1. Juli 2026, 1:30", "30. Juni 2026, 16:30"),
    ("ja_JP", "2026年7月1日 1:30", "2026年6月30日 16:30")
  ])
  func timestampsUseTheRequestedZoneAcrossCalendarDays(
    identifier: String, european: String, american: String
  ) throws {
    let locale = Locale(identifier: identifier)
    let prague = try #require(TimeZone(identifier: "Europe/Prague"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let instant = Date(timeIntervalSince1970: 1_782_862_200)
    #expect(CurrencyDisplay.timestamp(instant, locale: locale, timeZone: prague) == european)
    #expect(CurrencyDisplay.timestamp(instant, locale: locale, timeZone: losAngeles) == american)
  }

  @Test func timestampsObserveDaylightSavingTransitions() throws {
    let locale = Locale(identifier: "en_GB")
    let zone = try #require(TimeZone(identifier: "Europe/Prague"))
    let before = Date(timeIntervalSince1970: 1_774_744_200)
    let after = before.addingTimeInterval(3_600)
    #expect(CurrencyDisplay.timestamp(before, locale: locale, timeZone: zone).contains(" at 1:30"))
    #expect(CurrencyDisplay.timestamp(after, locale: locale, timeZone: zone).contains(" at 3:30"))
  }

  @Test func zoneNamesFollowTheRequestedLocale() throws {
    let zone = try #require(TimeZone(identifier: "Europe/Prague"))
    let english = CurrencyDisplay.timeZoneName(zone, locale: Locale(identifier: "en_GB"))
    let german = CurrencyDisplay.timeZoneName(zone, locale: Locale(identifier: "de_DE"))
    #expect(english == "Central European Time")
    #expect(german == "Mitteleuropäische Zeit")
  }

  @Test func hiddenProviderZonePreservesObservationAndContributors() {
    let source = RateSource(
      provider: .coinMetrics, observation: .minuteReference, timeZone: .gmt,
      conversion: .init(
        provider: .fawaz, published: "2026-10-14", value: 2,
        base: "EUR", quote: "USD"), contributingProviders: [.fawaz, .coinMetrics])
    let locale = Locale(identifier: "en_US")
    let hidden = RateMessages.providerDescription(source, locale: locale, includesTimeZone: false)
    #expect(hidden == "Coin Metrics + Fawaz · minute reference prices · approximate conversion")
    #expect(RateMessages.providerDescription(source, locale: locale) == hidden + " · GMT")
    #expect(source.timeZone == .gmt)
    #expect(source.observation == .minuteReference)
    #expect(source.contributingProviders == [.fawaz, .coinMetrics])
    #expect(
      RateMessages.conversionDescription(source, locale: locale)?.contains("Oct 14, 2026") == true)
    #expect(CurrencyDisplay.publicationDate("2026-10-14", locale: locale) == "Oct 14, 2026")
  }
}
