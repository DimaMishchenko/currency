import Foundation
import Testing

@testable import ExchangeRates

private let day = "2026-01-02"

@Suite struct RateSnapshotTests {
  @Test func crossRatesAndMissingCurrency() throws {
    let snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: day, source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: day, source: .init(provider: .custom("test"))),
      "BTC": ExchangeRate(
        try #require(Decimal(string: "0.00002")), published: day,
        source: .init(provider: .custom("test")))
    ])
    #expect(snapshot.convert(10, from: "USD", to: "EUR") == 5)
    #expect(snapshot.convert(1, from: "BTC", to: "USD") == 100000)
    #expect(snapshot.convert(10, from: "USD", to: "JPY") == nil)
    #expect(snapshot.convert(10, from: "USD", to: "USD") == 10)
  }

  @Test func cacheRoundTripAndCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RateCache(directory: directory)
    #expect(store.load().quotes.isEmpty)
    let snapshot = RateSnapshot(quotes: [
      "BTC": ExchangeRate(
        try #require(Decimal(string: "0.000012345678")), published: day,
        source: .init(provider: .custom("daily")))
    ])
    try store.save(snapshot)
    #expect(store.load().quotes == snapshot.quotes)
    try Data("broken".utf8).write(to: directory.appendingPathComponent("rates.json"))
    #expect(store.load().quotes.isEmpty)
  }
}
