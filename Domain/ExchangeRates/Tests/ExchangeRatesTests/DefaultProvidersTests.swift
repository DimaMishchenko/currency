import Foundation
import Testing

@testable import ExchangeRates

private actor DefaultProvidersHTTP: HTTPClient {
  private(set) var urls: [URL] = []
  var failing = false
  func failRequests() { failing = true }
  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    if failing { throw RateError.http(503) }
    if url.host == "community-api.coinmetrics.io" {
      return try JSONSerialization.data(withJSONObject: [
        "data": [
          [
            "asset": "btc", "time": Date().addingTimeInterval(-60).ISO8601Format(),
            "ReferenceRateUSD": "50000"
          ],
          [
            "asset": "eth", "time": Date().addingTimeInterval(-60).ISO8601Format(),
            "ReferenceRateUSD": "2500"
          ]
        ]
      ])
    }
    guard url.host == "cdn.jsdelivr.net" || url.host == "latest.currency-api.pages.dev" else {
      throw RateError.invalidData
    }
    let day = String(Date().ISO8601Format().prefix(10))
    return Data("{\"date\":\"\(day)\",\"eur\":{\"usd\":2,\"btc\":0.00002,\"eth\":0.0005}}".utf8)
  }
}

@Suite struct DefaultProvidersTests {
  @Test func refreshOverlaysCryptoAndFallsBackToUnmodifiedDailyOnFailure() async throws {
    let client = DefaultProvidersHTTP()
    let service = RateService(client: client)
    let now = Date()
    let first = await service.refresh(previous: RateSnapshot(), force: true, now: now)
    #expect(first.snapshot.quotes["BTC"]?.value == Decimal(string: "0.00004"))
    #expect(first.snapshot.quotes["BTC"]?.source.provider == .coinMetrics)
    #expect(first.snapshot.dailyQuotes?["BTC"]?.value == Decimal(string: "0.00002"))
    #expect(first.snapshot.quotes["USD"]?.source.provider == .fawaz)
    await client.failRequests()
    let fallback = await service.refresh(
      previous: first.snapshot, now: now.addingTimeInterval(1800))
    #expect(fallback.snapshot.quotes["BTC"]?.value == Decimal(string: "0.00002"))
    #expect(fallback.snapshot.quotes["BTC"]?.source.provider == .fawaz)
    #expect(fallback.warning == .partialCryptoFallback)
    #expect(await client.urls.filter { $0.host == "community-api.coinmetrics.io" }.count == 2)
    #expect(await client.urls.filter { $0.host == "cdn.jsdelivr.net" }.count == 3)
  }

  @Test func refreshAttemptsAreSpacedThirtyMinutes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DefaultProvidersHTTP()
    let now = Date()
    let store = RateStore(directory: directory)
    let service = RateService(client: client)
    _ = try await store.refreshRates(using: service, now: now)
    let initialRequests = await client.urls.count
    _ = try await store.refreshRates(using: service, now: now.addingTimeInterval(1799))
    #expect(await client.urls.count == initialRequests)
    _ = try await store.refreshRates(using: service, now: now.addingTimeInterval(1800))
    #expect(await client.urls.count > initialRequests)
  }

  @Test func storePreservesInjectedProviderQuotes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date()
    let daily = ExchangeRate(2, published: "2026-01-02", source: .init(provider: .custom("Daily")))
    let live = ExchangeRate(
      3, published: "2026-01-02", source: .init(provider: .custom("Crypto")), observedAt: now)
    let store = RateStore(directory: directory)
    let result = try await store.refreshRates(
      using: RateService(
        fiat: StubRateProvider(quotes: ["USD": daily]), daily: StubRateProvider(quotes: [:]),
        crypto: StubRateProvider(quotes: ["BTC": live])), now: now)
    #expect(result.snapshot.quotes["USD"]?.source.provider == .custom("Daily"))
    #expect(result.snapshot.quotes["BTC"] == live)
    #expect(store.loadRates().quotes == result.snapshot.quotes)
  }

  @Test func bootstrapUsesDailyAndCryptoProviders() async {
    let client = DefaultProvidersHTTP()
    var deliveries = 0
    for await update in await RateService(client: client).bootstrap(previous: RateSnapshot()) {
      deliveries += 1
      if update.isFinal {
        #expect(update.snapshot.quotes["BTC"]?.source.provider == .coinMetrics)
        #expect(update.snapshot.quotes["USD"]?.source.provider == .fawaz)
      }
    }
    #expect(deliveries == 2)
    #expect(await client.urls.contains { $0.host == "community-api.coinmetrics.io" })
    #expect(
      await client.urls.allSatisfy {
        $0.host == "community-api.coinmetrics.io" || $0.host == "cdn.jsdelivr.net"
      })
  }
}
