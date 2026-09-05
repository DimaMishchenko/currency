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
    #expect(store.widgetInput(key: first, codes: ["EUR", "JPY"]).amount == "1")
  }

  @Test func sameCurrencyPairRetainsEnteredAmount() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    try store.updateWidgetInput(key: "pair|same", codes: ["EUR", "EUR"]) { $0.press("7") }
    #expect(store.widgetInput(key: "pair|same", codes: ["EUR", "EUR"]).amount == "7")
  }

  @Test func resizePreservesInputAndKeepsActiveCurrencyOnAStablePage() throws {
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
    #expect(medium.visibleCodes(limit: 4) == ["CHF", "JPY"])
    #expect(medium.active == "JPY")
    #expect(medium.amount == "7")
    try store.updateWidgetInput(key: key, codes: codes) { $0.press("2") }
    var large = store.widgetInput(key: key, codes: codes)
    #expect(large.visibleCodes(limit: 8) == codes)
    #expect(large.active == "JPY")
    #expect(large.amount == "72")
    large.select("CHF", snapshot: rates)
    #expect(large.visibleCodes(limit: 4) == ["CHF", "JPY"])
    #expect(large.visibleCodes(limit: 0).isEmpty)
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
