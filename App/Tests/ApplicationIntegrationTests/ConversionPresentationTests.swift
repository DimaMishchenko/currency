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
    let row = ConversionPresentation.row(evaluation.results[0], request: request, style: .rate)
    #expect(!row.hasPrefix("0 "))
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
    #expect(result.resultText.contains("0.12") || result.resultText.contains("0,12"))
    #expect(result.status.isEmpty)
  }
  @Test func localAndFixedResultsKeepUsefulLabelsWithoutMetadataDump() throws {
    let local = ConversionDestination(local: nil, status: .denied, now: now)
    let request = try ConversionRequest(amount: "100", source: "EUR", destinations: [local])
    let evaluation = try ConversionEvaluation(request: request, snapshot: .init(), now: now)
    let result = ConversionResultEntity(result: evaluation.results[0], evaluation: evaluation)
    #expect(result.convertedAmount == nil && result.monetaryAmount == nil && result.currency == nil)
    #expect(result.resultText == String(localized: "Local currency"))
    #expect(result.status == ConversionPresentation.localSetup)
    #expect(ConversionPresentation.speech(evaluation) == ConversionPresentation.localSetup)
    #expect(!ConversionPresentation.speech(evaluation).contains("destination"))
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
  @Test func rateIsRoundedForPeopleWhileKeepingExactChainingData() throws {
    let request = try ConversionRequest(
      amount: "1", source: "USD", destinations: [.init(code: "EUR")])
    let snapshot = RateSnapshot(
      quotes: ["USD": quote(1), "EUR": quote(Decimal(string: "0.8773469")!)], fetchedAt: now)
    let evaluation = try ConversionEvaluation(request: request, snapshot: snapshot, now: now)
    let result = ConversionResultEntity(
      result: evaluation.results[0], evaluation: evaluation, style: .rate)
    #expect(result.convertedAmount == "0.8773469")
    #expect(result.resultText.contains("≈"))
    #expect(result.resultText.contains("🇺🇸") && result.resultText.contains("🇪🇺"))
    #expect(
      result.resultText.contains(CurrencyDisplay.format(Decimal(string: "0.88")!, code: "EUR")))
    let speech = ConversionPresentation.speech(evaluation, style: .rate)
    #expect(speech.contains("approximately") && !speech.contains("0.8773469"))
  }
  @Test func metalOutputsUseTroyOuncesAndCannotBeFiatMoney() throws {
    let request = try ConversionRequest(
      amount: "1", source: "XAU", destinations: [.init(code: "XAU")])
    let evaluation = try ConversionEvaluation(request: request, snapshot: .init(), now: now)
    let result = ConversionResultEntity(result: evaluation.results[0], evaluation: evaluation)
    #expect(result.monetaryAmount == nil)
    #expect(result.resultText.contains("troy oz") && result.resultText.contains("🥇"))
  }
  private func quote(_ value: Decimal) -> ExchangeRate {
    .init(value, published: "2027-01-15", source: .init(provider: .ecb))
  }
}
