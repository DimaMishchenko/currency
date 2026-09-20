import Foundation
import Testing

@testable import ExchangeRates

private actor CountingProvider: RateProvider {
  private(set) var calls = 0
  let quotes: [String: ExchangeRate]

  init(_ quotes: [String: ExchangeRate]) { self.quotes = quotes }

  func fetch() async throws -> [String: ExchangeRate] {
    calls += 1
    return quotes
  }
}

@Suite struct RefreshPolicyTests {
  @Test func dailyRefreshRespectsFreshnessBoundaryAndManualOverride() async {
    let now = Date(timeIntervalSince1970: 1_767_355_200)
    let quotes = [
      "EUR": ExchangeRate(1, published: "2026-01-02", source: .init(provider: .custom("test")))
    ]
    let provider = CountingProvider(quotes)
    let service = RateService(fiat: provider, daily: provider, crypto: nil)
    let previous = RateSnapshot(quotes: quotes, dailyQuotes: quotes, dailyFetchedAt: now)

    let reused = await service.refresh(previous: previous, now: now.addingTimeInterval(21_599))
    #expect(await provider.calls == 0)
    #expect(reused.snapshot.dailyFetchedAt == now)

    let expired = await service.refresh(previous: previous, now: now.addingTimeInterval(21_600))
    #expect(await provider.calls == 2)
    #expect(expired.snapshot.dailyFetchedAt == now.addingTimeInterval(21_600))

    _ = await service.refresh(previous: previous, force: true, now: now)
    #expect(await provider.calls == 4)
  }

  @Test func primaryFiatWinsEqualPublicationDates() async {
    let date = "2026-01-02"
    let primary = CountingProvider([
      "USD": ExchangeRate(2, published: date, source: .init(provider: .custom("primary")))
    ])
    let supplement = CountingProvider([
      "USD": ExchangeRate(3, published: date, source: .init(provider: .custom("supplement")))
    ])
    let result = await RateService(fiat: primary, daily: supplement, crypto: nil)
      .refresh(previous: RateSnapshot())
    #expect(result.snapshot.quotes["USD"]?.value == 2)
    #expect(result.snapshot.quotes["USD"]?.source.provider == .custom("primary"))
  }

  @Test func conversionRejectsInvalidAmountsAndRates() {
    let snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-01-02", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(0, published: "2026-01-02", source: .init(provider: .custom("test"))),
      "GBP": ExchangeRate(-1, published: "2026-01-02", source: .init(provider: .custom("test")))
    ])
    #expect(snapshot.convert(.nan, from: "EUR", to: "EUR") == nil)
    #expect(snapshot.convert(10, from: "USD", to: "EUR") == nil)
    #expect(snapshot.convert(10, from: "EUR", to: "GBP") == nil)
  }

  @Test func invalidDailyCacheCannotBecomeAnOfflineFallback() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RateCache(directory: directory)
    try store.save(
      RateSnapshot(
        quotes: [
          "BTC": ExchangeRate(1, published: "2026-01-02", source: .init(provider: .custom("live")))
        ],
        dailyQuotes: [
          "BTC": ExchangeRate(
            -1, published: "2026-01-02", source: .init(provider: .custom("corrupt")))
        ]
      ))
    #expect(store.load().quotes.isEmpty)
  }
}
