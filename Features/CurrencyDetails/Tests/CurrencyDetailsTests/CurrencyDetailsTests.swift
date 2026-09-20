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

  @Test func historyCapabilityReceivesBaseThenQuote() async {
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
    model.range = .quarter
    await model.load()
    #expect(requestedBase == "GBP")
    #expect(requestedQuote == "CZK")
    #expect(requestedRange == .quarter)
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
