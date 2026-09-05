import ExchangeRates
import Foundation
import Testing

@testable import CurrencySupport

private let day = "2026-01-02"

@Suite struct ConverterStateTests {
  @Test func keypad() {
    var input = ConverterState()
    input.press("AC")
    input.press("0")
    input.press(",")
    input.press(".")

    input.press("5")
    #expect(input.amount == "0.5")
    input.press("⌫")
    input.press("⌫")
    input.press("⌫")
    #expect(input.amount == "0")
    input.press("⇅")
    #expect(input.source == "USD")
    for _ in 0..<30 { input.press("9") }
    #expect(input.amount.count == 14)
  }

  @Test func legacyInputMigrationAndListNormalization() throws {
    let old = Data(#"{"amount":"12","from":"EUR","to":"USD"}"#.utf8)
    var input = try JSONDecoder().decode(ConverterState.self, from: old)
    #expect(input.destinations == ["USD", "GBP", "CZK", "JPY", "CHF", "BTC"])
    input.setDestinations(["GBP", "GBP", "EUR", "BAD", "USD"])
    #expect(input.destinations == ["GBP", "USD"])
    #expect(input.primaryDestination == "GBP")
    let restored = try JSONDecoder().decode(ConverterState.self, from: JSONEncoder().encode(input))
    #expect(restored.destinations == ["GBP", "USD"])
  }

  @Test func promoteCurrencyPreservesValueAndOrder() throws {
    var input = ConverterState()
    input.press("0")
    input.press("0")
    input.setDestinations(["USD", "GBP", "JPY"])
    let snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: day, source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(
        try #require(Decimal(string: "1.25")), published: day,
        source: .init(provider: .custom("test")))
    ])
    input.useAsBase("USD", snapshot: snapshot)
    #expect(input.source == "USD")
    #expect(input.amount == "125")
    #expect(input.destinations == ["EUR", "GBP", "JPY"])
    #expect(snapshot.convert(input.decimal, from: input.source, to: "EUR") == 100)
    let unchanged = input
    input.useAsBase("JPY", snapshot: snapshot)
    #expect(input == unchanged)
    input.press("⇅")
    #expect(input.source == "EUR")
    #expect(input.destinations == ["USD", "GBP", "JPY"])
  }

  @Test(arguments: [
    ("JPY", "1.5", "2"), ("KWD", "1.2345", "1.235"), ("BTC", "0.123456789", "0.12345679")
  ])
  func sourcePromotionRoundsAtDestinationPrecision(
    code: String, rate: String, expected: String
  ) throws {
    var input = ConverterState()
    input.setDestinations([code, "USD"])
    let snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: day, source: .init(provider: .custom("test"))),
      code: ExchangeRate(
        try #require(Decimal(string: rate)), published: day,
        source: .init(provider: .custom("test")))
    ])
    input.useAsBase(code, snapshot: snapshot)
    #expect(input.amount == expected)
    #expect(input.source == code)
    #expect(input.destinations == ["EUR", "USD"])
  }

  @Test func isolatedStorePersistsCoordinatedKeypadChangesAndRecoversCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    try store.press("AC")
    try store.press("4")
    try store.press("2")
    #expect(store.input().amount == "42")
    #expect(store.input().editedAt != nil)
    try Data("broken".utf8).write(to: directory.appendingPathComponent("input.json"))
    #expect(store.input().amount == "1")
  }

  @Test func renamedStateKeepsLegacyPersistenceKeys() throws {
    var state = ConverterState()
    state.changeSource("GBP")
    let data = try JSONEncoder().encode(state)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["from"] as? String == "GBP")
    #expect(json["source"] == nil)
    #expect(try JSONDecoder().decode(ConverterState.self, from: data) == state)
  }

  @Test func ignoredKeypadInputDoesNotPostponeWidgetRefresh() {
    var input = ConverterState()
    let original = input
    input.press("unsupported")
    #expect(input == original)
    input.press(".")
    let decimalEntered = input
    input.press(",")
    #expect(input == decimalEntered)
  }
}
