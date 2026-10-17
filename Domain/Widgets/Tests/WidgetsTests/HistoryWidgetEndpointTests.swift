import Conversion
import ExchangeRates
import Foundation
import Testing

@testable import Widgets

@Suite struct HistoryWidgetEndpointTests {
  @Test(arguments: [("BTC", "USD"), ("USD", "BTC"), ("BTC", "EUR"), ("EUR", "BTC")])
  func everyRangeUsesTheSharedQuote(base: String, quote: String) throws {
    let now = Date.now
    let rates = RateSnapshot(
      quotes: [
        "BTC": ExchangeRate(
          0.00001, published: "2026-10-16",
          source: .init(provider: .coinMetrics), observedAt: now.addingTimeInterval(-60)),
        "USD": ExchangeRate(1.2, published: "2026-10-16", source: .init(provider: .frankfurter)),
        "EUR": ExchangeRate(1, published: "2026-10-16", source: .init(provider: .frankfurter))
      ], fetchedAt: now)
    let pair = HistoryWidgetPair(app: ConverterState(), base: base, quote: quote)
    let request = try #require(pair.historyRequest)
    for range in HistoryRange.allCases {
      let history = HistoryResult(
        series: HistorySeries(
          points: [
            HistoryPoint(date: now.addingTimeInterval(-172800), value: 80000),
            HistoryPoint(date: now.addingTimeInterval(-86400), value: 90000)
          ], source: .init(provider: .fawaz), fetchedAt: now), issue: nil)
      let aligned = history.includingLatestQuote(
        from: rates, base: request.base, quote: request.quote, now: now)
      let shown = HistoryWidgetSnapshot(pair: pair, range: range, result: aligned)
      let expected = NSDecimalNumber(decimal: try #require(rates.convert(1, from: base, to: quote)))
        .doubleValue
      #expect(abs((shown.latest?.value ?? 0) - expected) < max(0.0000001, expected * 0.0000001))
      #expect(shown.latest == shown.series?.points.last)
    }
  }
}
