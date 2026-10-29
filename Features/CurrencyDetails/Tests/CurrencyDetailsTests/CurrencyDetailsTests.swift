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
  func finish(_ range: HistoryRange, series: HistorySeries? = nil, issue: HistoryIssue?) {
    requests.removeValue(forKey: range)?
      .resume(returning: HistoryResult(series: series, issue: issue))
  }
}

@Suite @MainActor
struct CurrencyDetailsTests {
  @Test(arguments: [HistoryRange.day, .week])
  func externalPeriodIsSelectedForTheFirstLoad(range: HistoryRange) async {
    var loaded: HistoryRange?
    let model = CurrencyDetailsModel(
      input: .init(code: "BTC", reference: "USD", snapshot: RateSnapshot(), initialRange: range),
      dependencies: .init(supportsIntraday: { _, _ in true }) { _, _, requested in
        loaded = requested
        return HistoryResult(series: nil, issue: .unavailable)
      })
    #expect(model.range == range)
    await model.load()
    #expect(loaded == range)
    model.updateSnapshot(RateSnapshot())
    #expect(model.range == range)
  }

  @Test func unsupportedExternalDayUsesMonth() {
    let model = CurrencyDetailsModel(
      input: .init(code: "EUR", reference: "USD", snapshot: RateSnapshot(), initialRange: .day),
      dependencies: .init(supportsIntraday: { _, _ in false }) { _, _, _ in
        HistoryResult(series: nil, issue: .unavailable)
      })
    #expect(model.range == .month)
  }

  @Test(arguments: [
    ("XAU", "USD", 3110.34768, 100.0), ("USD", "XAU", 0.01, 0.311034768),
    ("BTC", "XAU", 20.0, 622.069536), ("XAU", "BTC", 20.0, 0.05 / 31.1034768)
  ])
  func historyDisplaysSavedMetalUnitsWithoutChangingProviderValues(
    code: String, reference: String, canonicalValue: Double, expected: Double
  ) async {
    let canonical = HistorySeries(
      points: [HistoryPoint(date: .now, value: canonicalValue)],
      source: .init(provider: .custom("test")), fetchedAt: .now)
    let model = CurrencyDetailsModel(
      input: .init(code: code, reference: reference, snapshot: RateSnapshot(), metalUnit: .gram),
      dependencies: .init { _, _, _ in HistoryResult(series: canonical, issue: nil) })
    await model.load()
    #expect(abs((model.series?.points.first?.value ?? 0) - expected) < 0.0000001)
    #expect(canonical.points.first?.value == canonicalValue)
  }

  @Test(arguments: [
    ("EUR", "EUR", "USD"), ("USD", "USD", "EUR"), ("GBP", "GBP", "EUR"),
    ("BTC", "BTC", "USD")
  ])
  func sameCurrencyReferencesKeepTheirFallback(code: String, reference: String, quote: String) {
    let model = CurrencyDetailsModel(
      input: .init(code: code, reference: reference, snapshot: RateSnapshot()),
      dependencies: .init { _, _, _ in HistoryResult(series: nil, issue: .unavailable) })
    #expect(model.quote == quote)
  }

  @Test(arguments: CurrencyCatalog.codes)
  func distinctReferencesPreserveTheOriginatingPair(code: String) {
    for reference in ["USD", "EUR", "GBP", "CZK", "CHF", "BTC", "ETH", "XAU", "XAG"]
    where code != reference {
      let model = CurrencyDetailsModel(
        input: .init(code: code, reference: reference, snapshot: RateSnapshot()),
        dependencies: .init { _, _, _ in HistoryResult(series: nil, issue: .unavailable) })
      #expect(model.quote == reference)
    }
  }

  @Test(arguments: CurrencyCatalog.crypto.sorted(), ["USD", "EUR", "GBP", "CZK", "CHF", "ETH"])
  func cryptoPairRetainsQuoteConversionHistoryAndRanges(
    code: String, reference: String
  ) async throws {
    guard code != reference else { return }
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let source = RateSource(provider: .coinMetrics, observation: .minuteReference, timeZone: .gmt)
    let values: [String: Decimal] = [
      "USD": 2, "EUR": 1, "GBP": 3, "CZK": 25, "CHF": 4, "ETH": 5
    ]
    var quotes = values.mapValues {
      ExchangeRate($0, published: "2023-11-14", source: source, observedAt: date)
    }
    quotes[code] = ExchangeRate(
      8, published: "2023-11-14", source: source, observedAt: date)
    let snapshot = RateSnapshot(quotes: quotes, fetchedAt: date.addingTimeInterval(60))
    let expectedQuote = try #require(values[reference])
    let received = HistorySeries(
      points: [
        HistoryPoint(date: date.addingTimeInterval(-7200), value: 7),
        HistoryPoint(date: date.addingTimeInterval(-3600), value: 11)
      ], source: source, fetchedAt: date.addingTimeInterval(7200))
    var requests: [(String, String, HistoryRange)] = []
    let model = CurrencyDetailsModel(
      input: .init(code: code, reference: reference, snapshot: snapshot),
      dependencies: .init { base, quote, range in
        requests.append((base, quote, range))
        return HistoryResult(series: received, issue: .usingCachedSeries)
      })
    #expect(model.quote == reference)
    #expect(model.input.reference == reference)
    #expect(model.input.snapshot.quotes[code]?.source == source)
    #expect(model.input.snapshot.quotes[code]?.observedAt == date)
    #expect(model.input.snapshot.fetchedAt == snapshot.fetchedAt)
    #expect(model.input.snapshot.convert(1, from: code, to: model.quote) == expectedQuote / 8)
    if reference != "USD" {
      #expect(
        model.input.snapshot.convert(1, from: code, to: model.quote)
          != snapshot.convert(1, from: code, to: "USD"))
    }
    let ranges = model.availableRanges
    #expect(ranges == CurrencyDetailsModel.ranges)
    for range in ranges {
      model.range = range
      await model.load()
      #expect(model.quote == reference)
      #expect(requests.last?.0 == code)
      #expect(requests.last?.1 == reference)
      #expect(requests.last?.2 == range)
      #expect(model.series?.points.dropLast() == received.points[...])
      #expect(
        model.series?.points.last?.value == NSDecimalNumber(decimal: expectedQuote / 8).doubleValue)
      #expect(model.series?.points.last?.date == date)
      #expect(model.series?.source.provider == source.provider)
      #expect(model.series?.fetchedAt == received.fetchedAt)
      #expect(model.issue == .usingCachedSeries)
    }
    #expect(requests.count == ranges.count)
  }

  @Test(arguments: ["USD", "EUR", "GBP", "CZK", "CHF"], CurrencyCatalog.crypto.sorted())
  func fiatCryptoPairInvertsProviderSeriesAndRetainsProvenance(
    code: String, reference: String
  ) async {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let source = RateSource(provider: .coinMetrics, observation: .minuteReference, timeZone: .gmt)
    let received = HistorySeries(
      points: [
        HistoryPoint(date: date.addingTimeInterval(-7200), value: 40_000),
        HistoryPoint(date: date.addingTimeInterval(-3600), value: 50_000)
      ],
      source: source, fetchedAt: date.addingTimeInterval(7200))
    let snapshot = RateSnapshot(
      quotes: [
        code: ExchangeRate(4, published: "2023-11-14", source: source),
        reference: ExchangeRate(8, published: "2023-11-14", source: source, observedAt: date)
      ], fetchedAt: date.addingTimeInterval(60))
    var requestedRanges: [HistoryRange] = []
    let model = CurrencyDetailsModel(
      input: .init(code: code, reference: reference, snapshot: snapshot),
      dependencies: .init { base, quote, range in
        #expect(base == reference)
        #expect(quote == code)
        requestedRanges.append(range)
        return HistoryResult(series: received, issue: .usingCachedSeries)
      })
    #expect(model.availableRanges == CurrencyDetailsModel.ranges)
    #expect(model.input.snapshot.convert(1, from: code, to: model.quote) == 2)
    for range in model.availableRanges {
      model.range = range
      await model.load()
      #expect(model.quote == reference)
      #expect(model.series?.points.map(\.value) == [1.0 / 40_000, 1.0 / 50_000, 2])
      #expect(model.series?.points.map(\.date) == received.points.map(\.date) + [date])
      #expect(model.series?.source.provider == source.provider)
      #expect(model.series?.fetchedAt == received.fetchedAt)
      #expect(model.issue == .usingCachedSeries)
    }
    #expect(requestedRanges == model.availableRanges)
  }

  @Test(arguments: CurrencyCatalog.crypto.sorted(), CurrencyCatalog.metals.sorted())
  func metalCryptoPairsRetainReferenceWithoutIntraday(crypto: String, metal: String) async {
    for (code, reference) in [(crypto, metal), (metal, crypto)] {
      var requests: [(String, String, HistoryRange)] = []
      let model = CurrencyDetailsModel(
        input: .init(code: code, reference: reference, snapshot: RateSnapshot()),
        dependencies: .init { base, quote, range in
          requests.append((base, quote, range))
          return HistoryResult(series: nil, issue: .unavailable)
        })
      #expect(model.quote == reference)
      #expect(model.availableRanges == CurrencyDetailsModel.ranges.filter { $0 != .day })
      for range in model.availableRanges {
        model.range = range
        await model.load()
        #expect(model.quote == reference)
        #expect(requests.last?.0 == crypto)
        #expect(requests.last?.1 == metal)
        #expect(requests.last?.2 == range)
        #expect(model.issue == .unavailable)
      }
      #expect(requests.count == model.availableRanges.count)
    }
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

  @Test(arguments: [("BTC", true), ("ETH", true), ("USDC", true), ("EUR", false), ("USD", false)])
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

  @Test func injectedDailyCapabilityKeepsCryptoHistoryWithoutIntradayControls() async {
    var capabilityPair: [String] = []
    var requestedRange: HistoryRange?
    let model = CurrencyDetailsModel(
      input: .init(
        code: "EUR", reference: "BTC", snapshot: RateSnapshot()),
      dependencies: .init(
        supportsIntraday: { base, quote in
          capabilityPair = [base, quote]
          return false
        },
        loadHistory: { _, _, range in
          requestedRange = range
          return HistoryResult(series: nil, issue: .unavailable)
        }))
    #expect(!model.availableRanges.contains(.day))
    #expect(capabilityPair == ["BTC", "EUR"])
    #expect(model.availableRanges.contains(.month))
    await model.load()
    #expect(requestedRange == .month)
  }

  @Test func rangeChangesReplaceTheChartWithLoadingUntilTheRequestedHistoryArrives() async {
    let pending = PendingHistory()
    let model = CurrencyDetailsModel(
      input: .init(code: "EUR", reference: "USD", snapshot: RateSnapshot()),
      dependencies: .init { _, _, range in await pending.load(range) })
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    for (index, range) in [HistoryRange.month, .year, .month].enumerated() {
      model.range = range
      let request = Task { await model.load() }
      while pending.requests[range] == nil { await Task.yield() }
      #expect(model.phase == .loading)
      #expect(model.series == nil)
      #expect(model.issue == nil)
      let series = HistorySeries(
        points: [
          HistoryPoint(date: date, value: Double(index + 1)),
          HistoryPoint(date: date.addingTimeInterval(86400), value: Double(index + 2))
        ], source: .init(provider: .custom("test")), fetchedAt: date.addingTimeInterval(86400))
      pending.finish(range, series: series, issue: index == 0 ? .usingCachedSeries : nil)
      await request.value
      #expect(model.phase == .loaded)
      #expect(model.series?.points == series.points)
      #expect(model.issue == (index == 0 ? .usingCachedSeries : nil))
    }
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

@MainActor @Suite struct DetailsQuoteRefreshTests {
  @Test func refreshedQuotePreservesTheSelectedRangeAndHistoricalPrefix() async {
    let now = Date.now
    func rates(_ btc: Decimal, at date: Date) -> RateSnapshot {
      RateSnapshot(
        quotes: [
          "BTC": ExchangeRate(
            btc, published: "2026-10-16", source: .init(provider: .coinMetrics),
            observedAt: date),
          "USD": ExchangeRate(1, published: "2026-10-16", source: .init(provider: .frankfurter))
        ], fetchedAt: date)
    }
    var requests = 0
    let history = HistoryResult(
      series: HistorySeries(
        points: [
          HistoryPoint(date: now.addingTimeInterval(-7200), value: 40000),
          HistoryPoint(date: now.addingTimeInterval(-3600), value: 50000)
        ], source: .init(provider: .coinMetrics), fetchedAt: now), issue: nil)
    let model = CurrencyDetailsModel(
      input: .init(
        code: "BTC", reference: "USD", snapshot: rates(0.00001, at: now.addingTimeInterval(-60))),
      dependencies: .init { _, _, range in
        #expect(range == .year)
        requests += 1
        return history
      })
    model.range = .year
    await model.load()
    #expect(model.series?.points.last?.value == 100000)
    model.updateSnapshot(rates(0.00002, at: now))
    #expect(model.range == .year)
    #expect(model.phase == .loaded)
    #expect(requests == 1)
    #expect(model.input.snapshot.convert(1, from: "BTC", to: "USD") == 50000)
    #expect(model.series?.points.map(\.value) == [40000, 50000, 50000])
    #expect(model.series?.points.last?.date == now)
  }
}
