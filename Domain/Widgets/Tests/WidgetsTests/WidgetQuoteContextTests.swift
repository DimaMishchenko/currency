import ExchangeRates
import Foundation
import Testing

@testable import Widgets

@Suite struct WidgetQuoteContextTests {
  @Test func retainsRenderedQuoteAfterTheSharedCacheAdvancesAndExpires() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetQuoteContextStore(directory: directory)
    let now = Date.now
    let old = RateSnapshot(
      quotes: [
        "USD": ExchangeRate(
          1.1, published: "2026-10-16",
          source: .init(provider: .frankfurter))
      ], fetchedAt: now)
    let rates = RateStore(directory: directory)
    _ = try rates.saveBootstrapRates(old, now: now)
    let url = try #require(try store.save(old, now: now))
    let newer = RateSnapshot(
      quotes: [
        "USD": ExchangeRate(
          1.2, published: "2026-10-16",
          source: .init(provider: .frankfurter))
      ], fetchedAt: now.addingTimeInterval(60))
    _ = try rates.saveBootstrapRates(newer, now: now.addingTimeInterval(60))
    #expect(rates.loadRates().quotes["USD"]?.value == 1.2)
    let value = try #require(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "context" }?
        .value)
    let id = try #require(UUID(uuidString: value))
    #expect(try store.save(old, now: now.addingTimeInterval(60)) == url)
    #expect(store.load(id, now: now.addingTimeInterval(60))?.quotes["USD"]?.value == 1.1)
    #expect(store.load(id, now: now.addingTimeInterval(WidgetQuoteContextStore.lifetime)) == nil)
    #expect(store.load(UUID(), now: now) == nil)
    let pairURL = try #require(try store.save(old, base: "BTC", quote: "USD", now: now))
    #expect(pairURL != url)
    let pairValue = try #require(
      URLComponents(url: pairURL, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == "context" }?
        .value)
    let pairID = try #require(UUID(uuidString: pairValue))
    #expect(store.context(pairID, now: now)?.base == "BTC")
    #expect(store.context(pairID, now: now)?.quote == "USD")
  }
}
