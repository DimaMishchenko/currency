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

  @Test func defaultPairTracksBaseAndFirstDisplayedDestination() {
    var app = ConverterState()
    app.setDestinations(["CZK", "USD"])
    #expect(HistoryWidgetPair(app: app).base == "EUR")
    #expect(HistoryWidgetPair(app: app).quote == "CZK")
    app.setDestinations(["USD", "CZK"])
    #expect(HistoryWidgetPair(app: app).quote == "USD")
    app.changeSource("GBP")
    #expect(HistoryWidgetPair(app: app).base == "GBP")
    #expect(HistoryWidgetPair(app: app, base: "CHF", quote: "JPY").quote == "JPY")
    #expect(HistoryWidgetPair(app: app, base: "CHF").base == "CHF")
  }

  @Test func missingAndUnsupportedPairsAreNotSilentlySubstituted() {
    var app = ConverterState()
    app.setDestinations([])
    #expect(HistoryWidgetPair(app: app).quote == nil)
    for (base, quote) in [
      ("EUR", "EUR"), ("BTC", "EUR"), ("EUR", "BTC"), ("XAU", "USD"), ("invalid", "USD")
    ] {
      #expect(!HistoryWidgetPair(app: app, base: base, quote: quote).isSupported)
    }
    #expect(HistoryWidgetPair(app: app, base: "BTC", quote: "USD").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "USD", quote: "BTC").isSupported)
    #expect(HistoryWidgetPair(app: app, base: "EUR", quote: "CZK").isSupported)
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
}
