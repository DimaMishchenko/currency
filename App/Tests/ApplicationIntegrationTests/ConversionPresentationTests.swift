import Conversion
import ExchangeRates
import ExchangeRatesUI
import Foundation
import Testing

@Suite struct ConversionPresentationTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  @Test func sourceSpeechPreservesFractionalFiatAndJPY() throws {
    for code in ["EUR", "JPY"] {
      let request = try ConversionRequest(
        amount: "0.001", source: code, destinations: [.init(code: code)])
      let evaluation = try ConversionEvaluation(request: request, snapshot: .init(), now: now)
      let speech = ConversionPresentation.speech(evaluation)
      #expect(speech.contains("\(0.001.formatted(.number.precision(.fractionLength(3))))"))
      #expect(!speech.contains("Using cached rates"))
    }
  }
  @Test func positiveTinyRateAndAmountAreNeverPresentedAsZero() throws {
    let rates = RateSnapshot(
      quotes: ["EUR": quote(1), "IDR": quote(16000), "USD": quote(1)], fetchedAt: now)
    let request = try ConversionRequest(
      amount: "1", source: "IDR", destinations: [.init(code: "USD")])
    let evaluation = try ConversionEvaluation(request: request, snapshot: rates, now: now)
    let row = ConversionPresentation.row(evaluation.results[0], request: request)
    #expect(row != "0 USD")
    #expect(row.contains("625"))
    let tiny = try ConversionRequest(
      amount: "0.001", source: "EUR", destinations: [.init(code: "USD")])
    let result = try ConversionEvaluation(request: tiny, snapshot: rates, now: now)
    #expect(
      ConversionPresentation.row(result.results[0], request: tiny)
        .hasPrefix(String(localized: "Less than")))
  }
  @Test func resultExposesExactChainingValueAndReadableContext() throws {
    let request = try ConversionRequest(
      amount: "0.1234567890123456789012345678", source: "EUR", destinations: [.init(code: "EUR")])
    let evaluation = try ConversionEvaluation(request: request, snapshot: .init(), now: now)
    let result = ConversionResultEntity(result: evaluation.results[0], evaluation: evaluation)
    #expect(result.convertedAmount == request.amount)
    #expect(result.currency == "EUR")
    #expect(result.monetaryAmount?.amount == ExactAmount.parse(request.amount))
    #expect(result.resultText.hasSuffix("→ 0.12 EUR") || result.resultText.hasSuffix("→ 0,12 EUR"))
    #expect(result.status.isEmpty)
  }
  @Test func localAndFixedResultsKeepUsefulLabelsWithoutMetadataDump() throws {
    let local = ConversionDestination(local: nil, status: .denied, now: now)
    let request = try ConversionRequest(amount: "100", source: "EUR", destinations: [local])
    let evaluation = try ConversionEvaluation(request: request, snapshot: .init(), now: now)
    let result = ConversionResultEntity(result: evaluation.results[0], evaluation: evaluation)
    #expect(result.convertedAmount == nil && result.monetaryAmount == nil && result.currency == nil)
    #expect(result.resultText.hasSuffix("(Local)"))
    #expect(result.status == String(localized: "Local currency is unavailable"))
    #expect(!ConversionPresentation.speech(evaluation).contains("publication"))
  }
  @Test func individualStatusDoesNotInheritAnotherDestinationsFailure() throws {
    let request = try ConversionRequest(
      amount: "10", source: "EUR", destinations: [.init(code: "CZK"), .init(code: "BTC")])
    let rates = RateSnapshot(
      quotes: ["EUR": quote(1), "CZK": quote(25), "BTC": quote(0.00001)], fetchedAt: now,
      dailyFetchedAt: now)
    let evaluation = try ConversionEvaluation(
      request: request, snapshot: rates, now: now, warning: .partialCryptoFallback)
    let fiat = ConversionResultEntity(result: evaluation.results[0], evaluation: evaluation)
    let crypto = ConversionResultEntity(result: evaluation.results[1], evaluation: evaluation)
    #expect(fiat.status.isEmpty)
    #expect(crypto.status.contains(String(localized: "Daily cryptocurrency rates")))
  }
  @Test func oldPublicationRemainsDisclosedEvenWithRecentSharedFetchMetadata() throws {
    let request = try ConversionRequest(
      amount: "10", source: "EUR", destinations: [.init(code: "CZK")])
    let old = ExchangeRate(25, published: "2026-12-15", source: .init(provider: .ecb))
    let rates = RateSnapshot(quotes: ["EUR": quote(1), "CZK": old], fetchedAt: now)
    let evaluation = try ConversionEvaluation(request: request, snapshot: rates, now: now)
    let result = ConversionResultEntity(result: evaluation.results[0], evaluation: evaluation)
    #expect(!result.status.isEmpty)
    #expect(result.status.contains(CurrencyDisplay.publicationDate("2026-12-15")))
  }
  private func quote(_ value: Decimal) -> ExchangeRate {
    .init(value, published: "2027-01-15", source: .init(provider: .ecb))
  }
}
