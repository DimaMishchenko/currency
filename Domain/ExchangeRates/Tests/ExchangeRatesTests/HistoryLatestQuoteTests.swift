import Foundation
import Testing

@testable import ExchangeRates

@Suite struct HistoryLatestQuoteTests {
  private let now = Date(timeIntervalSince1970: 1_790_035_200)

  private func snapshot(observedAt: Date, btcPrice: Decimal = 52_500) -> RateSnapshot {
    let source = RateSource(provider: .coinMetrics, observation: .minuteReference, timeZone: .gmt)
    return RateSnapshot(
      quotes: [
        "EUR": ExchangeRate(1, published: "2026-09-22", source: .init(provider: .fawaz)),
        "USD": ExchangeRate(2, published: "2026-09-22", source: .init(provider: .fawaz)),
        "BTC": ExchangeRate(
          2 / btcPrice, published: "2026-09-22", source: source, observedAt: observedAt),
        "ETH": ExchangeRate(0.001, published: "2026-09-22", source: source, observedAt: observedAt)
      ], fetchedAt: now)
  }

  private func history(observation: RateObservation = .dailyReference) -> HistoryResult {
    .init(
      series: HistorySeries(
        points: [
          HistoryPoint(date: now.addingTimeInterval(-604800), value: 40_000),
          HistoryPoint(date: now.addingTimeInterval(-86400), value: 48_000),
          HistoryPoint(date: now, value: 50_000)
        ], source: .init(provider: .coinMetrics, observation: observation, timeZone: .gmt),
        fetchedAt: now), issue: nil)
  }

  @Test func sharedQuoteReplacesFutureChartSamplesAndKeepsThePeriodStart() throws {
    let observed = now.addingTimeInterval(-60)
    let result = history()
      .includingLatestQuote(
        from: snapshot(observedAt: observed), base: "BTC", quote: "USD", now: now)
    let series = try #require(result.series)
    #expect(series.points.dropLast().map(\.value) == [40_000, 48_000])
    #expect(abs(try #require(series.points.last?.value) - 52_500) < 0.000001)
    #expect(series.points.last?.date == observed)
    #expect(series.points.first?.date == now.addingTimeInterval(-604800))
    #expect(result.issue == nil)
  }

  @Test func conversionUsesTheSameSnapshotForFiatAndCryptoCrosses() throws {
    let rates = snapshot(observedAt: now)
    let euro = history().includingLatestQuote(from: rates, base: "BTC", quote: "EUR", now: now)
    #expect(abs(try #require(euro.series?.points.last?.value) - 26_250) < 0.000001)
    #expect(euro.series?.source.conversion?.value == 0.5)
    #expect(euro.series?.source.conversion?.published == "2026-09-22")
    #expect(euro.series?.source.contributingProviders == [.fawaz])
    let eth = history().includingLatestQuote(from: rates, base: "BTC", quote: "ETH", now: now)
    #expect(abs(try #require(eth.series?.points.last?.value) - 26.25) < 0.000001)
    #expect(eth.series?.source.conversion == nil)
  }

  @Test func minuteHistoryRetainsItsSamplingDescription() {
    let result = history(observation: .minuteReference)
      .includingLatestQuote(
        from: snapshot(observedAt: now), base: "BTC", quote: "USD", now: now)
    #expect(result.series?.source.observation == .minuteReference)
  }

  @Test func cachedQuoteKeepsItsActualObservationTimeAndWarning() throws {
    let observed = now.addingTimeInterval(-3600)
    let result = history()
      .includingLatestQuote(
        from: snapshot(observedAt: observed), base: "BTC", quote: "USD", now: now)
    #expect(result.series?.points.last?.date == observed)
    #expect(abs(try #require(result.series?.points.last?.value) - 52_500) < 0.000001)
    #expect(result.issue == .usingCachedSeries)
  }

  @Test func invalidMissingOrFutureQuotesDoNotInventAnEndpoint() {
    let missing = history()
      .includingLatestQuote(
        from: RateSnapshot(), base: "BTC", quote: "USD", now: now)
    #expect(missing.series?.points.last?.value == 50_000)
    #expect(missing.issue == .usingCachedSeries)
    let future = history()
      .includingLatestQuote(
        from: snapshot(observedAt: now.addingTimeInterval(60)), base: "BTC", quote: "USD", now: now)
    #expect(future.series?.points.last?.value == 50_000)
    #expect(future.issue == .usingCachedSeries)
  }

  @Test func missingHistoryAndDailyOnlyPairsKeepTheirExistingContract() {
    let rates = snapshot(observedAt: now)
    let missing = HistoryResult(series: nil, issue: .unavailable)
      .includingLatestQuote(from: rates, base: "BTC", quote: "USD", now: now)
    #expect(missing.series == nil)
    #expect(missing.issue == .unavailable)
    let fiat = history().includingLatestQuote(from: rates, base: "EUR", quote: "USD", now: now)
    #expect(fiat.series?.points.last?.value == 50_000)
  }

  @Test func futureLegCannotHideBehindAnOlderCrossQuote() {
    let current = snapshot(observedAt: now)
    var quotes = current.quotes
    let eth = quotes["ETH"]!
    quotes["ETH"] = ExchangeRate(
      eth.value, published: eth.published, source: eth.source,
      observedAt: now.addingTimeInterval(60))
    let result = history()
      .includingLatestQuote(
        from: RateSnapshot(quotes: quotes, fetchedAt: now), base: "BTC", quote: "ETH", now: now)
    #expect(result.series?.points.last?.value == 50_000)
    #expect(result.issue == .usingCachedSeries)
  }
}
