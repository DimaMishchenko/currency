import Conversion
import ExchangeRates
import Foundation
import Testing

@testable import Widgets

@Suite struct HistoryWidgetTests {
  private let now = Date(timeIntervalSince1970: 1_790_035_200)

  private func snapshot(_ values: [Double], issue: HistoryIssue? = nil) -> HistoryWidgetSnapshot {
    HistoryWidgetSnapshot(
      pair: HistoryWidgetPair(app: ConverterState(), base: "EUR", quote: "CZK"), range: .month,
      result: HistoryResult(
        series: HistorySeries(
          points: values.enumerated()
            .map { index, value in
              HistoryPoint(
                date: now.addingTimeInterval(Double(index - values.count) * 86_400), value: value)
            }, source: .init(provider: .frankfurter), fetchedAt: now), issue: issue))
  }

  @Test func metalHistoryScalesRateToSavedMassUnitWithoutChangingMovement() throws {
    var app = ConverterState()
    app.setMetalUnit(.gram)
    let pair = HistoryWidgetPair(app: app, base: "XAU", quote: "EUR")
    let provider = HistorySeries(
      points: [
        HistoryPoint(date: now.addingTimeInterval(-86_400), value: 2000),
        HistoryPoint(date: now, value: 2200)
      ], source: .init(provider: .custom("Metals")), fetchedAt: now)
    let shown = HistoryWidgetSnapshot(
      pair: pair, range: .month, result: .init(series: provider, issue: nil))
    let latest = try #require(shown.latest)
    let gramsPerOunce = NSDecimalNumber(decimal: MetalUnit.troyOunce.gramsPerUnit).doubleValue
    #expect(pair.metalUnit == .gram)
    #expect(abs(latest.value - 2200 / gramsPerOunce) < 0.000000001)
    #expect(shown.change == 0.1)
    #expect(shown.series?.source == provider.source)
  }

  @Test func missingAndUnsupportedPairsAreNotSilentlySubstituted() {
    var app = ConverterState()
    app.setDestinations([])
    #expect(HistoryWidgetPair(app: app).quote == nil)
    for (base, quote) in [("EUR", "EUR"), ("BTC", "BTC"), ("invalid", "USD")] {
      #expect(!HistoryWidgetPair(app: app, base: base, quote: quote).isSupported)
    }
    #expect(HistoryWidgetPair(app: app, base: "BTC", quote: "USD").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "USD", quote: "BTC").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "BTC", quote: "EUR").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "EUR", quote: "BTC").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "BTC", quote: "ETH").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "BTC", quote: "XAU").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "XAU", quote: "BTC").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "XAU", quote: "EUR").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "XAU", quote: "XAG").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "EUR", quote: "CZK").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "BTC", quote: "USD").supportsIntradayHistory)
    #expect(HistoryWidgetPair(app: app, base: "USD", quote: "BTC").supportsIntradayHistory)
    #expect(!HistoryWidgetPair(app: app, base: "EUR", quote: "CZK").supportsIntradayHistory)
    #expect(HistoryWidgetPair(app: app, base: "BTC", quote: "EUR").supportsIntradayHistory)
    #expect(HistoryWidgetPair(app: app, base: "EUR", quote: "BTC").supportsIntradayHistory)
    #expect(HistoryWidgetPair(app: app, base: "ETH", quote: "GBP").supportsIntradayHistory)
    #expect(!HistoryWidgetPair(app: app, base: "AVAX", quote: "GBP").supportsIntradayHistory)
    #expect(!HistoryWidgetPair(app: app, base: "USDC", quote: "USD").supportsIntradayHistory)
    #expect(HistoryWidgetPair(app: app, base: "BTC", quote: "USDC").supportsIntradayHistory)
    #expect(HistoryWidgetPair(app: app, base: "BTC", quote: "ETH").supportsIntradayHistory)
    #expect(HistoryWidgetPair(app: app, base: "ETH", quote: "BTC").supportsIntradayHistory)
    #expect(!HistoryWidgetPair(app: app, base: "BTC", quote: "XAU").supportsIntradayHistory)
    #expect(!HistoryWidgetPair(app: app, base: "XAU", quote: "BTC").supportsIntradayHistory)
    #expect(!HistoryWidgetPair(app: app, base: "XAU", quote: "EUR").supportsIntradayHistory)
  }

  @Test func fiatToBitcoinInvertsCrossRateHistory() {
    let pair = HistoryWidgetPair(app: ConverterState(), base: "EUR", quote: "BTC")
    let provider = HistorySeries(
      points: [
        HistoryPoint(date: now.addingTimeInterval(-86_400), value: 80_000),
        HistoryPoint(date: now, value: 100_000)
      ], source: .init(provider: .custom("Coinbase + Frankfurter")), fetchedAt: now)
    let shown = HistoryWidgetSnapshot(
      pair: pair, range: .month,
      result: HistoryResult(series: provider, issue: nil))
    #expect(pair.historyRequest?.base == "BTC")
    #expect(pair.historyRequest?.quote == "EUR")
    #expect(pair.historyRequest?.inverted == true)
    #expect(shown.series?.points.map(\.value) == [0.0000125, 0.00001])
    #expect(shown.change == -0.2)
  }

  @Test func metalToBitcoinInvertsCrossRateHistory() {
    let pair = HistoryWidgetPair(app: ConverterState(), base: "XAU", quote: "BTC")
    #expect(pair.historyRequest?.base == "BTC")
    #expect(pair.historyRequest?.quote == "XAU")
    #expect(pair.historyRequest?.inverted == true)
  }

  @Test func usdToBitcoinInvertsProviderHistoryWithoutChangingDatesOrSource() {
    let provider = snapshot([50_000, 100_000], issue: .usingCachedSeries).series!
    let pair = HistoryWidgetPair(app: ConverterState(), base: "USD", quote: "BTC")
    let shown = HistoryWidgetSnapshot(
      pair: pair, range: .month,
      result: HistoryResult(series: provider, issue: .usingCachedSeries))
    #expect(pair.historyRequest?.base == "BTC")
    #expect(pair.historyRequest?.quote == "USD")
    #expect(pair.historyRequest?.inverted == true)
    #expect(shown.series?.points.map(\.value) == [0.00002, 0.00001])
    #expect(shown.series?.points.map(\.date) == provider.points.map(\.date))
    #expect(shown.series?.source == provider.source)
    #expect(shown.series?.fetchedAt == provider.fetchedAt)
    #expect(shown.change == -0.5)
    #expect(shown.issue == .usingCachedSeries)
  }

  @Test func changeUsesFirstAndLastHistoricalObservation() {
    #expect(snapshot([20, 50, 25]).change == 0.25)
    #expect(snapshot([25, 50, 20]).change == -0.2)
    #expect(snapshot([25, 25]).change == 0)
    #expect(snapshot([25, 24.9999]).change == 0)
    #expect(snapshot([20, 25]).latest?.value == 25)
    #expect(snapshot([20, 25]).latest?.date == now.addingTimeInterval(-86_400))
  }

  @Test func unusableSeriesCannotProduceInventedGraphOrPercentage() {
    for values in [[], [25], [0, 25], [25, Double.infinity], [Double.nan, 25]] {
      let state = snapshot(values)
      #expect(state.series == nil)
      #expect(state.change == nil)
      #expect(state.issue == .unavailable)
    }
  }

  @Test func cachedHistoryKeepsObservationDateAndChange() {
    let saved = snapshot([20, 25], issue: .usingCachedSeries)
    #expect(saved.latest?.value == 25)
    #expect(saved.change == 0.25)
    #expect(saved.issue == .usingCachedSeries)
    #expect(saved.latest?.date != saved.series?.fetchedAt)
  }

  @Test func dailyScheduleUsesCacheExpiryAndDoesNotScheduleInPast() {
    let saved = snapshot([20, 25])
    #expect(
      saved.nextRefresh(after: now.addingTimeInterval(3600)) == now.addingTimeInterval(86_400))
    #expect(
      saved.nextRefresh(after: now.addingTimeInterval(90_000)) == now.addingTimeInterval(176_400))
    #expect(
      snapshot([20, 25], issue: .usingCachedSeries).nextRefresh(after: now)
        == now.addingTimeInterval(86_400))
  }

  @Test(arguments: HistoryRange.allCases)
  func supportedCryptoPairsScheduleNextHourEvenWhenHistoryIsUnavailable(range: HistoryRange) {
    let fetchedAt = now.addingTimeInterval(2220)
    for (base, quote) in [("USD", "BTC"), ("EUR", "BTC"), ("GBP", "ETH"), ("ETH", "BTC")] {
      let state = HistoryWidgetSnapshot(
        pair: HistoryWidgetPair(app: ConverterState(), base: base, quote: quote), range: range,
        result: HistoryResult(series: nil, issue: .unavailable))
      #expect(state.nextRefresh(after: fetchedAt) == now.addingTimeInterval(3600))
    }
  }

  @Test(arguments: [HistoryRange.week, .month, .quarter, .year, .yearToDate, .all])
  func fiatAndCryptoWithoutHourlyMarketsKeepDailyRefresh(range: HistoryRange) {
    for (base, quote) in [("EUR", "CZK"), ("BTC", "XAU"), ("AVAX", "GBP"), ("USDC", "USD")] {
      let state = HistoryWidgetSnapshot(
        pair: HistoryWidgetPair(app: ConverterState(), base: base, quote: quote), range: range,
        result: HistoryResult(series: nil, issue: .unavailable))
      #expect(state.nextRefresh(after: now) == now.addingTimeInterval(86_400))
    }
  }

  @Test func invertedMixedHistoryPreservesHourlyEndpointAndItsFetchAnchor() {
    let latest = HistoryPoint(date: now.addingTimeInterval(-3600), value: 84_608.1)
    let source = RateSource(
      provider: .coinbase, observation: .dailyClose, timeZone: .gmt,
      latestObservation: .hourlyClose)
    let provider = HistorySeries(
      points: [HistoryPoint(date: now.addingTimeInterval(-3 * 86400), value: 80_000), latest],
      source: source, fetchedAt: now)
    let state = HistoryWidgetSnapshot(
      pair: HistoryWidgetPair(app: ConverterState(), base: "USD", quote: "BTC"), range: .year,
      result: HistoryResult(series: provider, issue: nil))
    #expect(state.latest?.date == latest.date)
    #expect(state.latest?.value == 1 / latest.value)
    #expect(state.series?.source == source)
    #expect(state.series?.fetchedAt == now)
    #expect(state.change == ((80_000 / latest.value - 1) * 10_000).rounded() / 10_000)
    #expect(state.nextRefresh(after: now.addingTimeInterval(2220)) == now.addingTimeInterval(3600))
  }

  @Test(arguments: HistoryRange.allCases)
  func supportedCryptoSchedulesHourlyAcrossRanges(range: HistoryRange) {
    let series = HistorySeries(
      points: [
        HistoryPoint(date: now.addingTimeInterval(-3600), value: 24),
        HistoryPoint(date: now, value: 25)
      ], source: .init(provider: .coinbase, observation: .hourlyClose, timeZone: .gmt),
      fetchedAt: now)
    let pair = HistoryWidgetPair(app: ConverterState(), base: "BTC", quote: "USD")
    let fresh = HistoryWidgetSnapshot(
      pair: pair, range: range, result: HistoryResult(series: series, issue: nil))
    #expect(
      fresh.nextRefresh(after: now.addingTimeInterval(1200))
        == now.addingTimeInterval(3600))
    #expect(
      fresh.nextRefresh(after: now.addingTimeInterval(4000))
        == now.addingTimeInterval(7200))
    let stale = HistoryWidgetSnapshot(
      pair: pair, range: range,
      result: HistoryResult(series: series, issue: .usingCachedSeries))
    #expect(stale.nextRefresh(after: now) == now.addingTimeInterval(3600))
  }
}
