import Conversion
import ExchangeRates
import Foundation
import Testing

@testable import Widgets

@Suite struct HistoryWidgetEndpointTests {
  private let now = Date(timeIntervalSince1970: 1_790_035_200)

  private func result(
    _ values: [Double], offsets: [TimeInterval], intraday: Bool,
    issue: HistoryIssue? = nil, conversion: RateConversion? = nil
  ) -> HistoryResult {
    .init(
      series: .init(
        points: zip(values, offsets)
          .map {
            HistoryPoint(date: now.addingTimeInterval($0.1), value: $0.0)
          },
        source: .init(
          provider: intraday ? .coinMetrics : .fawaz,
          observation: intraday ? .minuteReference : .dailyReference,
          timeZone: .gmt, conversion: conversion), fetchedAt: now), issue: issue)
  }

  @Test(arguments: [HistoryRange.week, .month, .quarter, .year, .yearToDate, .all])
  func everyLongRangeSharesTheDayEndpoint(range: HistoryRange) {
    let pair = HistoryWidgetPair(app: ConverterState(), base: "BTC", quote: "USD")
    let daily = result([80_000, 82_158], offsets: [-604800, -86400], intraday: false)
    let minute = result([82_000, 81_596], offsets: [-86400, -300], intraday: true)
    let day = HistoryWidgetSnapshot(pair: pair, range: .day, result: minute)
    let week = HistoryWidgetSnapshot(pair: pair, range: range, result: daily, intraday: minute)
    #expect(week.latest == day.latest)
    #expect(week.series?.points.map(\.value) == [80_000, 82_158, 81_596])
    #expect(week.change == 0.0199)
    #expect(week.series?.source.provider == .coinMetrics)
    #expect(week.series?.source.observation == .unspecified)
    #expect(week.series?.source.contributingProviders == [.fawaz])
  }

  @Test(arguments: [("USD", "BTC"), ("EUR", "BTC"), ("ETH", "BTC")])
  func newestEndpointFollowsPairDirection(base: String, quote: String) {
    let pair = HistoryWidgetPair(app: ConverterState(), base: base, quote: quote)
    let daily = result([4, 5], offsets: [-604800, -86400], intraday: false)
    let minute = result([5, 8], offsets: [-86400, -300], intraday: true)
    let shown = HistoryWidgetSnapshot(pair: pair, range: .week, result: daily, intraday: minute)
    let inverted = pair.historyRequest?.inverted == true
    #expect(shown.latest?.value == (inverted ? 0.125 : 8))
    #expect(shown.change == (inverted ? -0.5 : 1))
    #expect(shown.latest?.date == minute.series?.points.last?.date)
  }

  @Test func mixedSeriesKeepsTheIntradayConversionInput() {
    let conversion = RateConversion(
      provider: .fawaz, published: "2026-09-22", value: 0.9, base: "USD", quote: "EUR")
    let pair = HistoryWidgetPair(app: ConverterState(), base: "BTC", quote: "EUR")
    let daily = result([80, 90], offsets: [-604800, -86400], intraday: false)
    let minute = result([90, 100], offsets: [-86400, -300], intraday: true, conversion: conversion)
    let shown = HistoryWidgetSnapshot(pair: pair, range: .week, result: daily, intraday: minute)
    #expect(shown.series?.source.conversion == conversion)
  }

  @Test func failedIntradayKeepsDailyGraphWithExplicitWarning() {
    let pair = HistoryWidgetPair(app: ConverterState(), base: "BTC", quote: "USD")
    let daily = result([80, 90], offsets: [-604800, -86400], intraday: false)
    let shown = HistoryWidgetSnapshot(
      pair: pair, range: .week, result: daily,
      intraday: .init(series: nil, issue: .unavailable))
    #expect(shown.series?.points == daily.series?.points)
    #expect(shown.series?.source == daily.series?.source)
    #expect(shown.issue == .usingCachedSeries)
  }

  @Test func staleIntradayKeepsItsObservationDateAndWarning() {
    let pair = HistoryWidgetPair(app: ConverterState(), base: "BTC", quote: "USD")
    let daily = result([80, 90], offsets: [-604800, -86400], intraday: false)
    let minute = result(
      [90, 100], offsets: [-86400, -3600], intraday: true, issue: .usingCachedSeries)
    let shown = HistoryWidgetSnapshot(pair: pair, range: .week, result: daily, intraday: minute)
    #expect(shown.latest == minute.series?.points.last)
    #expect(shown.issue == .usingCachedSeries)
  }

  @Test func invalidOrOlderIntradayCannotReplaceDailyEndpoint() {
    let pair = HistoryWidgetPair(app: ConverterState(), base: "BTC", quote: "USD")
    let daily = result([80, 90], offsets: [-604800, -86400], intraday: false)
    for minute in [
      result([90, 100], offsets: [-259200, -172800], intraday: true),
      result([90, .infinity], offsets: [-86400, -300], intraday: true),
      result([90, 100], offsets: [-86400, 300], intraday: true)
    ] {
      let shown = HistoryWidgetSnapshot(pair: pair, range: .week, result: daily, intraday: minute)
      #expect(shown.series?.points == daily.series?.points)
      #expect(shown.series?.source == daily.series?.source)
      if minute.series?.points.allSatisfy({ $0.value.isFinite && $0.date <= now }) == false {
        #expect(shown.issue == .usingCachedSeries)
      }
    }
  }

  @Test func equalDateIntradayReplacesTheDailyValueWithoutDuplicatingItsDate() {
    let pair = HistoryWidgetPair(app: ConverterState(), base: "BTC", quote: "USD")
    let daily = result([80, 90], offsets: [-604800, -86400], intraday: false)
    let minute = result([90, 100], offsets: [-172800, -86400], intraday: true)
    let shown = HistoryWidgetSnapshot(pair: pair, range: .week, result: daily, intraday: minute)
    #expect(shown.latest == minute.series?.points.last)
    #expect(shown.series?.points.count == 2)
    #expect(shown.series?.source.observation == .unspecified)
  }

  @Test func intradayCannotRescueAnUnavailableLongRange() {
    let pair = HistoryWidgetPair(app: ConverterState(), base: "BTC", quote: "USD")
    let shown = HistoryWidgetSnapshot(
      pair: pair, range: .week, result: .init(series: nil, issue: .unavailable),
      intraday: result([90, 100], offsets: [-86400, -300], intraday: true))
    #expect(shown.series == nil)
    #expect(shown.issue == .unavailable)
  }

  @Test func freshIntradayPreservesTheLongRangeCacheWarningAndUsesTheLatestFetchTime() {
    let pair = HistoryWidgetPair(app: ConverterState(), base: "BTC", quote: "USD")
    let daily = result([80, 90], offsets: [-604800, -86400], intraday: false)
    let saved = HistoryResult(
      series: daily.series.map {
        HistorySeries(
          points: $0.points, source: $0.source, fetchedAt: now.addingTimeInterval(-3600))
      }, issue: .usingCachedSeries)
    let minute = result([90, 100], offsets: [-86400, -300], intraday: true)
    let shown = HistoryWidgetSnapshot(pair: pair, range: .week, result: saved, intraday: minute)
    #expect(shown.latest == minute.series?.points.last)
    #expect(shown.issue == .usingCachedSeries)
    #expect(shown.series?.fetchedAt == minute.series?.fetchedAt)
  }

  @Test func pairsWithoutIntradayHistoryIgnoreAnUnrelatedIntradayResult() {
    let pair = HistoryWidgetPair(app: ConverterState(), base: "EUR", quote: "USD")
    let daily = result([0.8, 0.9], offsets: [-604800, -86400], intraday: false)
    let shown = HistoryWidgetSnapshot(
      pair: pair, range: .week, result: daily,
      intraday: result([90, 100], offsets: [-86400, -300], intraday: true))
    #expect(shown.series?.points == daily.series?.points)
    #expect(shown.series?.source == daily.series?.source)
    #expect(shown.issue == nil)
  }
}
