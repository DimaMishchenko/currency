import CurrencySupport
import ExchangeRates
import Foundation
import Testing

struct WidgetTests {
  private var rates: RateSnapshot {
    RateSnapshot(quotes: [
      "EUR": quote(1), "USD": quote(2), "CZK": quote(25),
      "XAU": quote(Decimal(string: "0.001") ?? 0)
    ])
  }

  private func quote(_ value: Decimal) -> ExchangeRate {
    ExchangeRate(value, published: "2026-09-04", source: .init(provider: .ecb))
  }

  @Test func selectionKeepsOrderAndNextDigitReplaces() {
    var state = WidgetInput(codes: ["EUR", "USD", "CZK"])
    state.press("5")
    state.select("USD", snapshot: rates)
    #expect(state.codes == ["EUR", "USD", "CZK"])
    #expect(state.active == "USD")
    #expect(state.decimal == 10)
    state.press("3")
    #expect(state.amount == "3")
    state.press("000")
    #expect(state.amount == "3000")
    state.select("EUR", snapshot: rates)
    #expect(state.decimal == 1500)
    state.press(".")
    state.press("5")
    #expect(state.amount == "0.5")
  }

  @Test func missingQuoteSelectionStillAllowsFreshInput() {
    var state = WidgetInput(codes: ["EUR", "BTC"])
    state.select("BTC", snapshot: rates)
    #expect(state.amount == "0")
    state.press("2")
    #expect(state.amount == "2")
    #expect(rates.convert(state.decimal, from: "BTC", to: "EUR") == nil)
  }

  @Test func selectingActiveCurrencyStartsFreshInputAndMarksInteraction() {
    var state = WidgetInput(codes: ["EUR", "USD"])
    state.press("4")
    state.press("2")
    state.select("EUR", snapshot: rates)
    #expect(state.amount == "42")
    #expect(state.editedAt != nil)
    state.press("7")
    #expect(state.amount == "7")
    let previous = state
    state.select("INVALID", snapshot: rates)
    #expect(state == previous)
  }

  @Test func ignoresOperatorsAndBoundsDigits() {
    var state = WidgetInput(codes: ["EUR", "USD"])
    let original = state
    for key in ["+", "-", "*", "/", "⇅", "nope"] { state.press(key) }
    #expect(state == original)
    for _ in 0..<20 { state.press("9") }
    #expect(state.amount.count == 14)
    state.press("AC")
    state.press("00")
    #expect(state.amount == "0")
    state.press("⌫")
    #expect(state.amount == "0")
    state.press(",")
    state.press(".")
    state.press("5")
    #expect(state.amount == "0.5")
  }

  @Test func independentWidgetIdentitiesPersistWithoutTouchingApp() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let codes = ["EUR", "USD"]
    let first = "multi|instance|" + UUID().uuidString
    let second = "multi|instance|" + UUID().uuidString
    try store.updateWidgetInput(key: first, codes: codes) { $0.press("7") }
    try store.updateWidgetInput(key: second, codes: codes) { $0.press("8") }
    try store.updateWidgetInput(key: first, codes: codes) { $0.press("2") }
    let reopened = CurrencyStore(directory: directory)
    #expect(reopened.widgetInput(key: first, codes: codes).amount == "72")
    #expect(reopened.widgetInput(key: second, codes: codes).amount == "8")
    #expect(store.input().amount == "1")
    #expect(store.widgetInput(key: first, codes: ["EUR", "JPY"]).amount == "72")
  }

  @Test func sameCurrencyPairRetainsEnteredAmount() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    try store.updateWidgetInput(key: "pair|same", codes: ["EUR", "EUR"]) { $0.press("7") }
    #expect(store.widgetInput(key: "pair|same", codes: ["EUR", "EUR"]).amount == "7")
  }

  @Test func resizePreservesCanonicalInputWithFixedVisiblePrefix() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let codes = ["EUR", "USD", "GBP", "CZK", "CHF", "JPY"]
    let key = "multi|instance|" + UUID().uuidString
    try store.updateWidgetInput(key: key, codes: codes) {
      $0.select("JPY", snapshot: rates)
      $0.press("7")
    }
    let medium = store.widgetInput(key: key, codes: codes)
    #expect(medium.visibleCodes(limit: 4) == Array(codes.prefix(4)))
    #expect(medium.active == "JPY")
    #expect(medium.amount == "7")
    try store.updateWidgetInput(key: key, codes: codes) { $0.press("2") }
    var large = store.widgetInput(key: key, codes: codes)
    #expect(large.visibleCodes(limit: 8) == codes)
    #expect(large.active == "JPY")
    #expect(large.amount == "72")
    large.select("CHF", snapshot: rates)
    #expect(large.visibleCodes(limit: 4) == Array(codes.prefix(4)))
    #expect(large.visibleCodes(limit: 0).isEmpty)
  }

  @Test func synchronizedListsRetainOrderAndSingleCurrencyWithoutFillers() {
    var app = ConverterState()
    app.setDestinations([])
    #expect(WidgetSelection.appCurrencies(app) == ["EUR"])
    let longList = Array(CurrencyCatalog.codes.prefix(20))
    app.setDestinations(longList)
    #expect(WidgetSelection.appCurrencies(app) == WidgetSelection.normalize(["EUR"] + longList))
    #expect(WidgetSelection.appCurrencies(app).count > 8)
    #expect(WidgetSelection.board(base: "USD", targets: ["USD", "EUR", "USD"]) == ["USD", "EUR"])
    #expect(WidgetSelection.board(base: "EUR", targets: ["EUR"]) == ["EUR"])
    #expect(
      WidgetSelection.normalize(["EUR", "@local", "USD", "@local"], allowsLocal: true)
        == ["EUR", "@local", "USD"])
  }

  @Test func reconciliationPreservesSurvivingInputAndResetsRemovedCurrency() {
    var input = WidgetInput(codes: ["EUR", "USD", "CZK"])
    input.select("USD", snapshot: rates)
    input.press("7")
    input.reconcile(codes: ["CZK", "USD", "JPY"])
    #expect(input.active == "USD")
    #expect(input.amount == "7")
    input.reconcile(codes: ["JPY"])
    #expect(input.active == "JPY")
    #expect(input.amount == "1")
  }

  @Test func listOwnershipAndLocalPositionAreIndependentOfResolution() {
    var app = ConverterState()
    app.setDestinations(["USD", "GBP"])
    let custom = ["JPY", "@local", "CZK"]
    #expect(
      WidgetSelection.calculator(app: app, custom: nil, usesCustom: true, includeLocal: false)
        .isEmpty)
    #expect(
      WidgetSelection.calculator(app: app, custom: custom, usesCustom: true, includeLocal: false)
        == custom)
    app.setDestinations(["CHF"])
    #expect(
      WidgetSelection.calculator(app: app, custom: custom, usesCustom: true, includeLocal: false)
        == custom)
    #expect(
      WidgetSelection.calculator(app: app, custom: custom, usesCustom: false, includeLocal: true)
        == ["EUR", "CHF", "@local"])
    let location = WidgetLocation(country: "CZ", currency: "CZK")
    let success = WidgetResolvedSelection(codes: custom, location: location, status: .available)
    #expect(success.canonical == custom)
    #expect(success.codes == ["JPY", "@local:CZK", "CZK"])
    #expect(success.localCode == "CZK")
    let failed = WidgetResolvedSelection(codes: custom, location: location, status: .failed)
    #expect(failed.codes == success.codes)
    #expect(failed.localIsStale)
    for status in [WidgetLocationStatus.notDetermined, .denied, .restricted, .removed] {
      let unresolved = WidgetResolvedSelection(codes: custom, location: location, status: status)
      #expect(unresolved.codes == custom)
      #expect(unresolved.localCode == nil)
    }
    #expect(WidgetResolvedSelection(codes: custom, location: nil, status: .failed).codes == custom)
    #expect(WidgetInput(codes: ["@local", "EUR"]).active == "EUR")
  }

  @Test func staleLocationUsabilityIsSeparateFromPrivacyStatus() {
    let location = WidgetLocation(country: "CZ", currency: "CZK", updatedAt: .distantPast)
    #expect(!location.isFresh())
    #expect(location.isUsable)
    #expect(WidgetLocationStatus.failed.allowsCache)
    for status in [WidgetLocationStatus.denied, .restricted, .removed, .notDetermined] {
      #expect(!status.allowsCache)
    }
  }

  @Test func resizeProjectsEquivalentValueWithoutSavingUntilInteraction() throws {
    let rates = RateSnapshot(quotes: ["EUR": quote(1), "JPY": quote(175)])
    let codes = ["EUR", "USD", "GBP", "CZK", "CHF", "JPY"]
    var input = WidgetInput(codes: codes)
    input.select("JPY", snapshot: rates)
    input.press("7")
    let saved = try JSONEncoder().encode(input)
    var medium = input.displayedInput(limit: 4, snapshot: rates)
    #expect(medium.active == "EUR")
    #expect(medium.decimal == rates.convert(7, from: "JPY", to: "EUR"))
    #expect(medium.codes == codes)
    let restored = try JSONDecoder().decode(WidgetInput.self, from: saved)
    #expect(restored.displayedInput(limit: 8, snapshot: rates).active == "JPY")
    #expect(restored.amount == "7")
    medium.press("2")
    #expect(medium.active == "EUR")
    #expect(medium.amount == "2")
    #expect(medium.displayedInput(limit: 8, snapshot: rates).active == "EUR")
  }

  @Test(arguments: [4, 8]) func defaultReservesLocalWithoutChangingCustomOrder(limit: Int) {
    let fixed = Array(CurrencyCatalog.codes.prefix(limit))
    for local in [WidgetSelection.localID, "@local:CZK"] {
      let input = WidgetInput(codes: fixed + [local])
      #expect(input.visibleCodes(limit: limit) == fixed)
      #expect(
        input.visibleCodes(limit: limit, reservesLocal: true) == Array(fixed.prefix(limit - 1)) + [
          local
        ])
      #expect(input.codes == fixed + [local])
    }
  }

  @Test func hiddenUnavailableCurrencyRetainsItsValue() {
    var input = WidgetInput(codes: ["EUR", "USD", "GBP", "CZK", "BTC"])
    input.select("BTC", snapshot: rates)
    input.press("7")
    let medium = input.displayedInput(limit: 4, snapshot: rates)
    #expect(medium.active == "BTC")
    #expect(medium.amount == "7")
    #expect(!medium.visibleCodes(limit: 4).contains(medium.active))
    #expect(input.displayedInput(limit: 8, snapshot: rates).amount == "7")
  }

  @Test func localDuplicateKeepsSeparateTileAndConvertsUsingItsCurrency() {
    var input = WidgetInput(codes: ["EUR", "CZK", "@local:CZK"], amount: "7")
    input.select("@local:CZK", snapshot: rates)
    #expect(input.active == "@local:CZK")
    #expect(input.amount == "175")
    #expect(input.codes.count == 3)
    input.select("CZK", snapshot: rates)
    #expect(input.amount == "175")
  }

  @Test func synchronizedValuePreservesWidgetSelectionAndCustomRemainsIndependent() {
    var app = ConverterState()
    app.setAmount("7")
    var synced = WidgetInput(codes: ["EUR", "CZK"])
    synced.select("CZK", snapshot: rates)
    synced.synchronize(with: app, snapshot: rates)
    #expect(synced.active == "CZK")
    #expect(synced.amount == "175")
    let custom = WidgetInput(codes: ["EUR", "CZK"], amount: "3")
    app.setAmount("8")
    synced.synchronize(with: app, snapshot: rates)
    #expect(synced.amount == "200")
    #expect(custom.amount == "3")
    #expect(app.source == "EUR")
  }

  @Test(arguments: ["EUR", "USD", "CZK", "CHF", "JPY", "BTC"])
  func defaultTypingSurvivesConversionAndTimelineReload(code: String) throws {
    let values: [String: Decimal] = [
      "EUR": 1, "USD": 1.17, "CZK": 24.657, "CHF": 0.913784, "JPY": 172.934, "BTC": 0.000012534
    ]
    let rates = RateSnapshot(
      quotes: values.mapValues {
        ExchangeRate($0, published: "2026-09-07", source: .init(provider: .ecb))
      })
    var app = ConverterState()
    app.setAmount("7")
    var input = WidgetInput(codes: ["EUR", "USD", "CZK", "CHF", "JPY", "BTC"])
    input.synchronize(with: app, snapshot: rates)
    input.select(code, snapshot: rates)
    for key in ["1", "2", ".", "3"] {
      input.press(key)
      input.publish(to: &app, snapshot: rates)
      input = try JSONDecoder().decode(WidgetInput.self, from: JSONEncoder().encode(input))
      input.synchronize(with: app, snapshot: rates)
    }
    #expect(input.active == code)
    #expect(input.amount == "12.3")
    #expect(app.amount != "7")
    app.setAmount("9")
    input.synchronize(with: app, snapshot: rates)
    #expect(input.decimal == rates.convert(9, from: "EUR", to: code))
  }

  @Test func missingRateDoesNotDisableSelectedDefaultTile() {
    var app = ConverterState()
    app.setAmount("7")
    var input = WidgetInput(codes: ["EUR", "USD", "BTC"])
    input.select("BTC", snapshot: rates)
    input.synchronize(with: app, snapshot: rates)
    input.press("8")
    input.publish(to: &app, snapshot: rates)
    input.synchronize(with: app, snapshot: rates)
    #expect(input.active == "BTC")
    #expect(input.amount == "8")
    #expect(app.amount == "7")
  }

  @Test func defaultWidgetPublishesAtMostTwoFractionDigitsToApp() throws {
    var app = ConverterState()
    var input = WidgetInput(codes: ["EUR", "USD"], amount: "1.239")
    input.publish(to: &app, snapshot: rates)
    #expect(app.amount == "1.24")

    input = WidgetInput(codes: ["USD", "EUR"], amount: "14.399")
    input.publish(to: &app, snapshot: rates)
    #expect(app.amount == "7.2")
  }

  @Test func banknotesAndMetalsHaveDifferentUnits() throws {
    #expect(WidgetPresets.amounts("CZK") == [100, 500, 1000])
    #expect(WidgetPresets.amounts("JPY") == [1000, 5000, 10000])
    #expect(WidgetPresets.amounts("XAU") == [1, 10, 1000])
    #expect(!WidgetPresets.isBanknote("XAU"))
    #expect(!WidgetPresets.allows("BTC"))
    #expect(!WidgetPresets.allows("XDR"))
    #expect(
      WidgetPresets.convert(
        WidgetPresets.gramsPerTroyOunce, from: "XAU", to: "EUR", snapshot: rates) == 1000)
    let grams = try #require(WidgetPresets.convert(1000, from: "EUR", to: "XAU", snapshot: rates))
    #expect(grams == WidgetPresets.gramsPerTroyOunce)
    #expect(WidgetPresets.convert(10, from: "XAU", to: "XAU", snapshot: rates) == 10)
  }

  @Test func referenceRulesAreUsefulAndBounded() throws {
    #expect(WidgetMath.anchor(rate: 25) == 1)
    #expect(WidgetMath.anchor(rate: Decimal(string: "0.04") ?? 0) == 500)
    let division = try #require(WidgetMath.rule(rate: Decimal(string: "0.04") ?? 0))
    #expect(division.divide)
    #expect(division.factor == 25)
    #expect(division.error == 0)
    let multiplication = try #require(WidgetMath.rule(rate: Decimal(string: "24.93") ?? 0))
    #expect(!multiplication.divide)
    #expect(multiplication.factor == 25)
    #expect(multiplication.error < Decimal(string: "0.01") ?? 0)
    #expect(WidgetMath.rule(rate: 0) == nil)
    #expect(WidgetMath.rule(rate: .nan) == nil)
  }

  @Test func validatesConfiguredAmounts() {
    #expect(WidgetMath.parseAmount("12,50") == Decimal(string: "12.5"))
    for bad in ["-1", "1e5", "12abc", "1,000.00", "", "NaN"] {
      #expect(WidgetMath.parseAmount(bad) == nil)
    }
    #expect(WidgetMath.parseAmount("0") == 0)
  }

  @Test func localCurrencyRequiresFreshSupportedCountry() throws {
    let now = Date()
    #expect(WidgetLocation.currency(for: "CZ") == "CZK")
    #expect(WidgetLocation.currency(for: "US") == "USD")
    #expect(WidgetLocation.currency(for: "XX") == nil)
    #expect(WidgetLocation(country: "CZ", currency: "CZK", updatedAt: now).isFresh(now: now))
    #expect(
      !WidgetLocation(country: "CZ", currency: "CZK", updatedAt: now.addingTimeInterval(-86400))
        .isFresh(now: now))
    #expect(!WidgetLocation(country: "CZ", currency: "BTC", updatedAt: now).isFresh(now: now))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let local = WidgetLocation(country: "CZ", currency: "CZK", updatedAt: now)
    try store.saveWidgetLocation(local)
    #expect(store.widgetLocation() == local)
    try store.saveWidgetLocation(nil)
    #expect(store.widgetLocation() == nil)
  }
}
