import Conversion
import ExchangeRates
import Foundation
import LocalCurrency
import Testing

@Suite struct ExternalConversionTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  @Test(arguments: [
    "0", "000.1200", ".5", "12,34", "12345678901234567890123456789012345678",
    "0." + String(repeating: "0", count: 120) + "1"
  ])
  func exactAmountsRoundTrip(_ text: String) throws {
    let amount = try #require(ExactAmount.parse(text))
    #expect(ExactAmount.parse(ExactAmount.string(amount)) == amount)
  }
  @Test(arguments: [
    "", ".", "-1", "1e2", "NaN", "1,234.5", "1 000", "１２", "1..2",
    "123456789012345678901234567890123456789012345678901"
  ])
  func invalidOrUnrepresentableAmountsFail(_ text: String) {
    #expect(ExactAmount.parse(text) == nil)
  }
  @Test func canonicalInputAndZero() throws {
    let request = try ConversionRequest(
      amount: "000,000", source: "EUR", destinations: [.init(code: "USD")])
    #expect(request.amount == "0")
    let result = try ConversionEvaluation(request: request, snapshot: snapshot(), now: now)
    #expect(result.results[0].amount == "0")
  }
  @Test func duplicateFixedAndLocalKeepIdentityAndPartialOrder() throws {
    let local = ConversionDestination(
      local: .init(country: "CZ", currency: "CZK", updatedAt: now), status: .available, now: now)
    let request = try ConversionRequest(
      amount: "10", source: "EUR", destinations: [.init(code: "CZK"), .init(code: "BTC"), local])
    let result = try ConversionEvaluation(request: request, snapshot: snapshot(), now: now)
    #expect(result.results.map(\.id) == ["CZK", "BTC", "@local"])
    #expect(result.results.map(\.amount) == ["250", nil, "250"])
    #expect(!result.dailyFallback)
  }
  @Test func identityCalculationsNeedNoRatesAndHaveNoCacheWarning() throws {
    let request = try ConversionRequest(
      amount: "0.00000001", source: "BTC", destinations: [.init(code: "BTC")])
    let result = try ConversionEvaluation(request: request, snapshot: .init(), now: now)
    #expect(result.results[0].amount == "0.00000001")
    #expect(result.fetchedAt == nil)
    #expect(!result.cacheIsStale && !result.dailyFallback && !result.refreshFailed)
  }
  @Test func unrelatedCryptoWarningDoesNotMarkFiatConversionFailed() throws {
    let request = try ConversionRequest(
      amount: "1", source: "EUR", destinations: [.init(code: "CZK")])
    let result = try ConversionEvaluation(
      request: request, snapshot: snapshot(), now: now, warning: .partialCryptoFallback)
    #expect(!result.refreshFailed && !result.dailyFallback)
  }
  @Test func freshCryptoFetchCannotMakeOldDailyLegsCurrentInsideTheThrottle() throws {
    let oldDaily = now.addingTimeInterval(-30 * 86400)
    let request = try ConversionRequest(
      amount: "10", source: "EUR", destinations: [.init(code: "CZK")])
    let rates = RateSnapshot(
      quotes: [
        "EUR": quote(1), "CZK": quote(25),
        "BTC": .init(
          0.00001, published: "2027-01-15", source: .init(provider: .coinbase),
          retrievedAt: now)
      ], fetchedAt: now, dailyFetchedAt: oldDaily, checkedAt: now)
    let evaluation = try ConversionEvaluation(request: request, snapshot: rates, now: now)
    #expect(evaluation.results[0].amount == "250")
    #expect(evaluation.results[0].cacheIsStale && evaluation.cacheIsStale)
    #expect(!evaluation.refreshFailed)
  }
  @Test func cryptoFallbackStatusDoesNotAffectHealthyFiatResult() throws {
    let request = try ConversionRequest(
      amount: "10", source: "EUR", destinations: [.init(code: "CZK"), .init(code: "BTC")])
    let rates = RateSnapshot(
      quotes: [
        "EUR": quote(1), "CZK": quote(25),
        "BTC": .init(0.00001, published: "2027-01-15", source: .init(provider: .fawaz))
      ], fetchedAt: now, dailyFetchedAt: now, checkedAt: now)
    let evaluation = try ConversionEvaluation(
      request: request, snapshot: rates, now: now, warning: .partialCryptoFallback)
    #expect(!evaluation.results[0].refreshFailed && !evaluation.results[0].dailyFallback)
    #expect(evaluation.results[1].refreshFailed && evaluation.results[1].dailyFallback)
    #expect(evaluation.refreshFailed && evaluation.dailyFallback)
  }
  @Test func partialFiatResponsePreservesLegacyQuoteAge() async throws {
    let oldFetch = now.addingTimeInterval(-21601)
    let euro = ExchangeRate(1, published: "2027-01-15", source: .init(provider: .ecb))
    let dollar = ExchangeRate(2, published: "2027-01-15", source: .init(provider: .ecb))
    let previous = RateSnapshot(
      quotes: ["EUR": euro, "USD": dollar], fetchedAt: oldFetch,
      dailyQuotes: ["EUR": euro, "USD": dollar], dailyFetchedAt: oldFetch)
    let fresh = await RateService(
      fiat: PartialFiatProvider(quotes: ["EUR": euro]),
      daily: PartialFiatProvider(quotes: [:]), crypto: nil
    )
    .refresh(previous: previous, now: now)
    let request = try ConversionRequest(
      amount: "1", source: "EUR", destinations: [.init(code: "USD")])
    let evaluation = try ConversionEvaluation(request: request, snapshot: fresh.snapshot, now: now)
    #expect(evaluation.results[0].amount == "2")
    #expect(fresh.snapshot.fiatFetchedAt == now)
    #expect(fresh.snapshot.quotes["USD"]?.cachedAt == oldFetch)
    #expect(evaluation.cacheIsStale)
  }

  @Test func customLiveProviderDoesNotProduceDailyFallbackWarning() throws {
    let request = try ConversionRequest(
      amount: "1", source: "BTC", destinations: [.init(code: "ETH")])
    let source = RateSource(provider: .custom("market"), observation: .exchangeRate)
    let rates = RateSnapshot(
      quotes: [
        "BTC": .init(2, published: "2027-01-15", source: source, retrievedAt: now),
        "ETH": .init(4, published: "2027-01-15", source: source, retrievedAt: now)
      ], fetchedAt: now)
    let evaluation = try ConversionEvaluation(
      request: request, snapshot: rates, now: now, warning: .dailyRatesUnavailable)
    #expect(!evaluation.dailyFallback && !evaluation.refreshFailed && !evaluation.cacheIsStale)
  }

  @Test func deniedLocalNeverUsesSavedObservationButStalePermissionCan() throws {
    let location = WidgetLocation(
      country: "CZ", currency: "CZK", updatedAt: now.addingTimeInterval(-100000))
    let denied = ConversionDestination(local: location, status: .denied, now: now)
    #expect(denied.code == nil && denied.localObservation == nil)
    let stale = ConversionDestination(local: location, status: .failed, now: now)
    #expect(stale.code == "CZK" && stale.localIsStale)
    let request = try ConversionRequest(amount: "10", source: "EUR", destinations: [denied])
    let evaluation = try ConversionEvaluation(request: request, snapshot: snapshot(), now: now)
    #expect(evaluation.results[0].availability == .localUnavailable)
    #expect(evaluation.results[0].sourceQuote == nil && evaluation.results[0].targetQuote == nil)
  }
  @Test func missingMetadataAndOverflowNeverBecomeZero() throws {
    let request = try ConversionRequest(
      amount: "1", source: "EUR", destinations: [.init(code: "USD")])
    let invalid = RateSnapshot(quotes: snapshot().quotes)
    #expect(
      try ConversionEvaluation(request: request, snapshot: invalid, now: now).results[0]
        .availability == .missingRates)
    let huge = try #require(ExactAmount.parse("1" + String(repeating: "0", count: 127)))
    let largeRequest = try ConversionRequest(
      amount: ExactAmount.string(huge), source: "EUR", destinations: [.init(code: "USD")])
    let largeRates = RateSnapshot(quotes: ["EUR": quote(1), "USD": quote(huge)], fetchedAt: now)
    let result = try ConversionEvaluation(request: largeRequest, snapshot: largeRates, now: now)
    #expect(result.results[0].availability == .overflow)
    #expect(result.results[0].amount == nil)
  }
  private func quote(_ value: Decimal) -> ExchangeRate {
    ExchangeRate(value, published: "2027-01-15", source: .init(provider: .ecb))
  }
  private func snapshot() -> RateSnapshot {
    RateSnapshot(
      quotes: ["EUR": quote(1), "USD": quote(2), "CZK": quote(25)], fetchedAt: now, checkedAt: now)
  }
}

private struct PartialFiatProvider: RateProvider {
  let quotes: [String: ExchangeRate]
  func fetch() async throws -> [String: ExchangeRate] { quotes }
}
