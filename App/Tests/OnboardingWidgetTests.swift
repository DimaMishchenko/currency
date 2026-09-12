import CurrencySupport
import ExchangeRates
import Foundation
import Testing
import WidgetPresentation

@testable import WidgetOnboardingFeature

@MainActor
struct OnboardingWidgetTests {
  private var rates: RateSnapshot {
    RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-10", source: .init(provider: .custom("Test"))),
      "USD": ExchangeRate(2, published: "2026-09-10", source: .init(provider: .custom("Test"))),
      "GBP": ExchangeRate(4, published: "2026-09-10", source: .init(provider: .custom("Test"))),
      "BTC": ExchangeRate(0.001, published: "2026-09-10", source: .init(provider: .custom("Test")))
    ])
  }

  @Test func personalizedPreviewUsesSuppliedRatesAndDoesNotMutateAppInput() {
    var input = ConverterState()
    input.setAmount("100")
    input.setDestinations(["USD", "GBP", "CZK"])
    let configuration = OnboardingWidgetConfiguration(
      kind: .calculator, snapshot: rates, input: input)
    #expect(configuration.codes == ["EUR", "USD", "GBP"])
    #expect(!configuration.isSample)
    #expect(configuration.snapshot.convert(100, from: "EUR", to: "USD") == 200)
    var preview = WidgetPreviewState(
      kind: .calculator, snapshot: configuration.snapshot, codes: configuration.codes,
      amount: configuration.input.amount)
    preview.apply(
      WidgetCommand("select:USD", spec: WidgetSpec(kind: "preview", codes: configuration.codes)))
    #expect(preview.input.decimal == 200)
    #expect(input.source == "EUR")
    #expect(input.destinations == ["USD", "GBP", "CZK"])
    #expect(input.amount == "100")
  }

  @Test func pairWidgetsChooseFirstUsableDestinationWithoutFallbackNumbers() {
    var input = ConverterState()
    input.setDestinations(["CZK", "GBP", "USD"])
    for kind in [WidgetShowcaseKind.pocket, .mental, .quick] {
      let configuration = OnboardingWidgetConfiguration(kind: kind, snapshot: rates, input: input)
      #expect(configuration.codes == ["EUR", "GBP"])
      #expect(configuration.input.primaryDestination == "GBP")
      #expect(configuration.snapshot.quotes["CZK"] == nil)
      #expect(!configuration.isSample)
    }
  }

  @Test func cashUsesRealCompatiblePairOrExplicitSamplesForCrypto() {
    var input = ConverterState()
    input.setDestinations(["BTC", "USD"])
    let fiat = OnboardingWidgetConfiguration(kind: .cash, snapshot: rates, input: input)
    #expect(fiat.codes == ["EUR", "USD"])
    #expect(!fiat.isSample)
    input.changeSource("BTC")
    let crypto = OnboardingWidgetConfiguration(kind: .cash, snapshot: rates, input: input)
    #expect(crypto.isSample)
    #expect(crypto.codes == WidgetShowcaseKind.cash.codes)
    #expect(input.source == "BTC")
  }

  @Test func editedPreviewUsesLiveStateWithExplicitCodesAndNewRates() {
    let codes = ["EUR", "USD", "GBP"]
    let spec = WidgetSpec(kind: "preview", codes: codes)
    var state = WidgetPreviewState(kind: .calculator, snapshot: rates, codes: codes, amount: "100")
    state.apply(WidgetCommand("select:USD", spec: spec))
    state.apply(WidgetCommand("7", spec: spec))
    state.apply(WidgetCommand("5", spec: spec))
    var updatedQuotes = rates.quotes
    updatedQuotes["GBP"] = ExchangeRate(6, published: "2026-09-11", source: .init(provider: .ecb))
    state.update(snapshot: RateSnapshot(quotes: updatedQuotes), codes: codes, amount: "100")
    let entry = state.entry()
    #expect(entry.input.active == "USD")
    #expect(entry.input.amount == "75")
    #expect(entry.spec.amount == "75")
    #expect(entry.input.codes == codes)
    #expect(entry.snapshot.convert(entry.input.decimal, from: "USD", to: "GBP") == 225)
  }

  @Test func resizedCalculatorPreservesHiddenActiveValueAndCanonicalCodesUntilNextKey() {
    let codes = ["EUR", "USD", "GBP", "JPY", "CZK", "CHF", "CAD", "AUD"]
    var snapshot = rates.quotes
    for (index, code) in codes.enumerated() where snapshot[code] == nil {
      snapshot[code] = ExchangeRate(
        Decimal(index + 1), published: "2026-09-10", source: .init(provider: .ecb))
    }
    let allRates = RateSnapshot(quotes: snapshot)
    var state = WidgetPreviewState(
      kind: .calculator, snapshot: allRates, codes: codes, amount: "100")
    state.apply(WidgetCommand("select:AUD", spec: state.entry().spec))
    let edited = state.input
    // Large→medium projects the hidden active tile without truncating or saving its display list.
    let medium = state.entry().input.displayedInput(limit: 4, snapshot: allRates)
    #expect(medium.active == "EUR")
    #expect(medium.decimal == 100)
    #expect(state.entry().input == edited)
    #expect(state.entry().input.visibleCodes(limit: 8) == codes)
    state.update(snapshot: allRates, codes: codes, amount: "100")
    #expect(state.input == edited)
    state.apply(
      WidgetCommand(
        "2", spec: state.entry().spec, activeCurrency: medium.active, hiddenCurrency: edited.active)
    )
    #expect(state.input.active == "EUR")
    #expect(state.input.amount == "2")
    #expect(state.input.codes == codes)
  }

  @Test func previewEditsNeverWriteAppOrInstalledWidgetState() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let codes = ["EUR", "USD"]
    try store.updateInput { $0.setAmount("42") }
    let installed = try store.updateWidgetInput(key: "installed-calculator", codes: codes) {
      $0.preset(17)
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    let before = try Dictionary(
      uniqueKeysWithValues: files.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    var calculator = WidgetPreviewState(
      kind: .calculator, snapshot: rates, codes: codes, amount: "100")
    var cash = WidgetPreviewState(kind: .cash, snapshot: rates, codes: codes, amount: "100")
    calculator.apply(WidgetCommand("select:USD", spec: calculator.entry().spec))
    calculator.apply(WidgetCommand("9", spec: calculator.entry().spec))
    cash.apply(WidgetCommand("preset:50", spec: cash.entry().spec))
    cash.update(snapshot: rates, codes: codes, amount: "100")
    #expect(calculator.input.amount == "9")
    #expect(cash.entry().input.amount == "50")
    #expect(store.input().amount == "42")
    #expect(store.widgetInput(key: "installed-calculator", codes: codes) == installed)
    let afterFiles = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    let after = try Dictionary(
      uniqueKeysWithValues: afterFiles.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    #expect(after == before)
  }

  @Test func uneditedTutorialPreviewStillFollowsExternalAmountAndCurrencyChanges() {
    var state = WidgetPreviewState(
      kind: .calculator, snapshot: rates, codes: ["EUR", "USD"], amount: "100")
    state.update(snapshot: rates, codes: ["GBP", "USD"], amount: "25")
    #expect(state.entry().input.active == "GBP")
    #expect(state.entry().input.amount == "25")
    #expect(state.entry().spec.codes == ["GBP", "USD"])
    // An empty custom tutorial configuration must still show the real choose-currencies state.
    state.update(snapshot: rates, codes: [], amount: "25")
    #expect(state.entry(configuredCodes: []).spec.codes.isEmpty)
  }

  @Test func homeScreenEntrancePausesWithoutRestartAndReduceMotionSettlesImmediately() {
    let start = Date(timeIntervalSince1970: 100)
    var clock = HomeScreenEntranceClock()
    clock.setActive(true, reduceMotion: false, now: start)
    clock.setActive(false, reduceMotion: false, now: start.addingTimeInterval(0.25))
    clock.setActive(false, reduceMotion: false, now: start.addingTimeInterval(10))
    #expect(!clock.isRunning)
    #expect(clock.time(at: start.addingTimeInterval(20)) == 0.25)
    clock.setActive(true, reduceMotion: false, now: start.addingTimeInterval(20))
    #expect(clock.time(at: start.addingTimeInterval(20.25)) == 0.5)
    clock.setActive(true, reduceMotion: true, now: start.addingTimeInterval(20.25))
    #expect(!clock.isRunning)
    #expect(clock.time(at: start.addingTimeInterval(21)) == HomeScreenEntranceClock.duration)
    clock.setActive(true, reduceMotion: false, now: start.addingTimeInterval(22))
    #expect(!clock.isRunning)
  }

}
