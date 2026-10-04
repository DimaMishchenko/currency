import CurrencyDetails
import ExchangeRates
import Foundation
import Testing

@MainActor
private final class PendingHistory {
  var requests: [HistoryRange: CheckedContinuation<HistoryResult, Never>] = [:]
  func load(_ range: HistoryRange) async -> HistoryResult {
    await withCheckedContinuation { requests[range] = $0 }
  }
  func finish(_ range: HistoryRange, issue: HistoryIssue?) {
    requests.removeValue(forKey: range)?.resume(returning: HistoryResult(series: nil, issue: issue))
  }
}

@Suite @MainActor
struct CurrencyDetailsTests {
  @Test func quotePolicyPreservesCryptoHistoryAndDistinctFiatReferences() {
    for (code, reference, quote) in [
      ("BTC", "CZK", "USD"), ("EUR", "EUR", "USD"), ("USD", "USD", "EUR"),
      ("GBP", "BTC", "EUR"), ("GBP", "CZK", "CZK")
    ] {
      let model = CurrencyDetailsModel(
        input: .init(code: code, reference: reference, snapshot: RateSnapshot()),
        dependencies: .init { _, _, _ in HistoryResult(series: nil, issue: .unavailable) })
      #expect(model.quote == quote)
    }
  }

  @Test(arguments: [("BTC", "EUR"), ("EUR", "BTC"), ("BTC", "ETH")])
  func explicitlyRequestedPairPreservesChartAndRateQuote(code: String, reference: String) async {
    var requested: [String] = []
    let model = CurrencyDetailsModel(
      input: .init(
        code: code, reference: reference, snapshot: RateSnapshot(), referencePolicy: .requestedPair),
      dependencies: .init { base, quote, _ in
        requested = [base, quote]
        return HistoryResult(series: nil, issue: .unavailable)
      })
    #expect(model.quote == reference)
    await model.load()
    #expect(requested == (code == "EUR" ? [reference, code] : [code, reference]))
  }

  @Test func requestedFiatCryptoPairInvertsProviderSeriesAndRetainsProvenance() async {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let source = RateSource(provider: .coinbase, observation: .hourlyClose, timeZone: .gmt)
    let received = HistorySeries(
      points: [
        HistoryPoint(date: date, value: 40_000),
        HistoryPoint(date: date.addingTimeInterval(3600), value: 50_000)
      ],
      source: source, fetchedAt: date.addingTimeInterval(7200))
    let model = CurrencyDetailsModel(
      input: .init(
        code: "EUR", reference: "BTC", snapshot: RateSnapshot(), referencePolicy: .requestedPair),
      dependencies: .init { base, quote, _ in
        #expect(base == "BTC")
        #expect(quote == "EUR")
        return HistoryResult(series: received, issue: .usingCachedSeries)
      })
    #expect(model.availableRanges.contains(.day))
    model.range = .day
    await model.load()
    #expect(model.quote == "BTC")
    #expect(model.series?.points.map(\.value) == [1.0 / 40_000, 1.0 / 50_000])
    #expect(model.series?.points.map(\.date) == received.points.map(\.date))
    #expect(model.series?.source == source)
    #expect(model.series?.fetchedAt == received.fetchedAt)
    #expect(model.issue == .usingCachedSeries)
  }

  @Test(arguments: CurrencyDetailsModel.ranges)
  func historyCapabilityReceivesBaseThenQuote(range: HistoryRange) async {
    var requestedBase: String?
    var requestedQuote: String?
    var requestedRange: HistoryRange?
    let model = CurrencyDetailsModel(
      input: .init(code: "GBP", reference: "CZK", snapshot: RateSnapshot()),
      dependencies: .init { base, quote, range in
        requestedBase = base
        requestedQuote = quote
        requestedRange = range
        return HistoryResult(series: nil, issue: .unavailable)
      })
    model.range = range
    await model.load()
    #expect(requestedBase == "GBP")
    #expect(requestedQuote == "CZK")
    #expect(requestedRange == range)
  }

  @Test(arguments: [("BTC", true), ("ETH", true), ("USDC", false), ("EUR", false), ("USD", false)])
  func chartOffersIntradayOnlyForSupportedHistory(code: String, supportsIntraday: Bool) {
    let model = CurrencyDetailsModel(
      input: .init(code: code, reference: "USD", snapshot: RateSnapshot()),
      dependencies: .init { _, _, _ in HistoryResult(series: nil, issue: .unavailable) })
    #expect(model.availableRanges.contains(.day) == supportsIntraday)
    #expect(model.availableRanges.contains(.quarter))
    #expect(model.availableRanges.contains(.yearToDate))
    #expect(
      CurrencyDetailsModel.ranges == [.day, .week, .month, .quarter, .yearToDate, .year, .all])
  }

  @Test func supersededNoncooperatingRequestCannotReplaceNewerRange() async {
    let pending = PendingHistory()
    let model = CurrencyDetailsModel(
      input: .init(code: "EUR", reference: "USD", snapshot: RateSnapshot()),
      dependencies: .init { _, _, range in await pending.load(range) })
    let old = Task { await model.load() }
    while pending.requests[.month] == nil { await Task.yield() }
    model.range = .year
    let current = Task { await model.load() }
    while pending.requests[.year] == nil { await Task.yield() }
    pending.finish(.year, issue: .usingCachedSeries)
    await current.value
    pending.finish(.month, issue: .unavailable)
    await old.value
    #expect(model.issue == .usingCachedSeries)
    #expect(model.phase == .loaded)
  }

  @Test func teardownRejectsLateResult() async {
    let pending = PendingHistory()
    let model = CurrencyDetailsModel(
      input: .init(code: "EUR", reference: "USD", snapshot: RateSnapshot()),
      dependencies: .init { _, _, range in await pending.load(range) })
    let task = Task { await model.load() }
    while pending.requests[.month] == nil { await Task.yield() }
    model.stop()
    pending.finish(.month, issue: .unavailable)
    await task.value
    #expect(model.issue == nil)
    #expect(model.series == nil)
  }

  @Test func cancellationDoesNotPublishUnavailableState() async {
    let pending = PendingHistory()
    let model = CurrencyDetailsModel(
      input: .init(code: "EUR", reference: "USD", snapshot: RateSnapshot()),
      dependencies: .init { _, _, range in await pending.load(range) })
    let task = Task { await model.load() }
    while pending.requests[.month] == nil { await Task.yield() }
    task.cancel()
    pending.finish(.month, issue: .unavailable)
    await task.value
    #expect(model.issue == nil)
  }
}
