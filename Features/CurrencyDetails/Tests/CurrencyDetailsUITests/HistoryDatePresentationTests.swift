import ExchangeRates
import Foundation
import Testing

@testable import CurrencyDetailsUI

@Suite struct HistoryDatePresentationTests {
  @Test(arguments: [
    ("America/Los_Angeles", "2026-10-21T00:30:00Z", "20 Oct 2026", "17:30"),
    ("Asia/Tokyo", "2026-10-20T23:30:00Z", "21 Oct 2026", "08:30")
  ])
  func intradayLabelsUseLocalCalendarDayAndTime(
    zone: String, instant: String, day: String, time: String
  ) throws {
    let dates = try presentation(range: .day, observation: .minuteReference, zone: zone)
    let date = try #require(ISO8601DateFormatter().date(from: instant))
    #expect(dates.pointLabel(date).contains(day))
    #expect(dates.pointLabel(date).contains(time))
    #expect(date.formatted(dates.axisFormat) == time)
    #expect(date.formatted(dates.timestampFormat).contains(time))
  }

  @Test func weeklyHourlyObservationsUseLocalInstants() throws {
    let dates = try presentation(
      range: .week, observation: .hourlyReference, zone: "America/Los_Angeles")
    let date = try #require(ISO8601DateFormatter().date(from: "2026-10-21T00:30:00Z"))
    #expect(dates.showsTime)
    #expect(dates.pointLabel(date).contains("20 Oct 2026"))
    #expect(dates.pointLabel(date).contains("17:30"))
    #expect(date.formatted(dates.axisFormat).contains("20"))
  }

  @Test(arguments: [
    ("2026-03-08T09:30:00Z", "01:30"), ("2026-03-08T10:30:00Z", "03:30")
  ])
  func daylightSavingTransitionUsesTheOffsetAtEachInstant(instant: String, time: String) throws {
    let dates = try presentation(
      range: .day, observation: .minuteReference, zone: "America/Los_Angeles")
    let date = try #require(ISO8601DateFormatter().date(from: instant))
    #expect(date.formatted(dates.axisFormat) == time)
    #expect(dates.pointLabel(date).contains(time))
    #expect(date.formatted(dates.timestampFormat).contains(time))
  }

  @Test(arguments: [RateObservation.dailyReference, .monthlyReference])
  func referenceDatesKeepProviderCalendarDayAcrossTimeZones(observation: RateObservation) throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z"))
    let range: HistoryRange = observation == .monthlyReference ? .all : .month
    let utc = try presentation(range: range, observation: observation, zone: "GMT")
    for zone in ["America/Los_Angeles", "Pacific/Kiritimati"] {
      let dates = try presentation(range: range, observation: observation, zone: zone)
      #expect(!dates.showsTime)
      #expect(dates.pointLabel(date) == "1 Jan 2026")
      #expect(dates.pointLabel(date) == utc.pointLabel(date))
      #expect(date.formatted(dates.axisFormat) == date.formatted(utc.axisFormat))
      #expect(dates.timestampFormat.timeZone.identifier == zone)
    }
  }

  @Test func retrievalTimestampsStayLocalForDateOnlyHistory() throws {
    let dates = try presentation(
      range: .month, observation: .dailyReference, zone: "America/Los_Angeles")
    let date = try #require(ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z"))
    #expect(dates.pointLabel(date) == "1 Jan 2026")
    let timestamp = date.formatted(dates.timestampFormat)
    #expect(timestamp.contains("31 Dec 2025"))
    #expect(timestamp.contains("16:00"))
  }

  @Test func chartTimeZoneNamesTheDisplayZone() throws {
    let dates = try presentation(
      range: .day, observation: .minuteReference, zone: "America/Los_Angeles")
    #expect(dates.chartTimeZone == "Pacific Time")
  }

  private func presentation(
    range: HistoryRange, observation: RateObservation, zone: String
  ) throws -> HistoryDatePresentation {
    HistoryDatePresentation(
      range: range, observation: observation, locale: Locale(identifier: "en_GB"),
      timeZone: try #require(TimeZone(identifier: zone)))
  }
}
