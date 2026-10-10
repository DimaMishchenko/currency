import Foundation
import Testing

@testable import ExchangeRates

private actor PolicyHTTP: HTTPClient {
  private(set) var urls: [URL] = []
  var failing = false
  func failRequests() { failing = true }
  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    if failing { throw RateError.http(503) }
    if url.host == "api.coinbase.com" {
      return Data(
        #"{"data":{"currency":"EUR","rates":{"EUR":"1","BTC":"0.00003","ETH":"0.0006"}}}"#.utf8)
    }
    guard url.host == "cdn.jsdelivr.net" || url.host == "latest.currency-api.pages.dev" else {
      throw RateError.invalidData
    }
    let day = String(Date().ISO8601Format().prefix(10))
    return Data("{\"date\":\"\(day)\",\"eur\":{\"usd\":2,\"btc\":0.00002,\"eth\":0.0005}}".utf8)
  }
}

@Suite struct RateProviderPolicyTests {
  @Test func dailyRefreshAndBootstrapNeverContactCoinbaseOrFrankfurter() async throws {
    let client = PolicyHTTP()
    let service = RateService(client: client)
    let first = await service.refresh(previous: RateSnapshot(), force: true)
    #expect(first.snapshot.quotes["BTC"]?.source.provider == .fawaz)
    #expect(first.snapshot.quotes["USD"]?.value == 2)
    #expect(first.warning == nil)
    var deliveries = 0
    for await update in await service.bootstrap(previous: first.snapshot) {
      deliveries += 1
      #expect(update.isFinal)
      #expect(update.snapshot.quotes.values.allSatisfy { $0.source.provider == .fawaz })
    }
    #expect(deliveries == 1)
    #expect(await client.urls.count == 2)
    #expect(await client.urls.allSatisfy { $0.host == "cdn.jsdelivr.net" })
  }

  @Test func enabledRefreshOverlaysCryptoAndFallsBackToUnmodifiedDailyOnFailure() async throws {
    let client = PolicyHTTP()
    let service = RateService(policy: .coinbaseEnhanced, client: client)
    let now = Date()
    let first = await service.refresh(previous: RateSnapshot(), force: true, now: now)
    #expect(first.snapshot.quotes["BTC"]?.value == Decimal(string: "0.00003"))
    #expect(first.snapshot.quotes["BTC"]?.source.provider == .coinbase)
    #expect(first.snapshot.dailyQuotes?["BTC"]?.value == Decimal(string: "0.00002"))
    #expect(first.snapshot.quotes["USD"]?.source.provider == .fawaz)
    await client.failRequests()
    let fallback = await service.refresh(
      previous: first.snapshot, now: now.addingTimeInterval(1800))
    #expect(fallback.snapshot.quotes["BTC"]?.value == Decimal(string: "0.00002"))
    #expect(fallback.snapshot.quotes["BTC"]?.source.provider == .fawaz)
    #expect(fallback.warning == .partialCryptoFallback)
    #expect(await client.urls.filter { $0.host == "api.coinbase.com" }.count == 2)
    #expect(await client.urls.filter { $0.host == "cdn.jsdelivr.net" }.count == 1)
  }

  @Test(arguments: [false, true])
  func disabledStoreFiltersAllCacheDictionariesAndBootstrap(legacy: Bool) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date()
    let daily = ExchangeRate(2, published: "2026-01-01", source: .init(provider: .fawaz))
    let live = ExchangeRate(
      3, published: "2026-01-02",
      source: .init(
        provider: .coinbase,
        observation: .exchangeRate), retrievedAt: now)
    let foreign = ExchangeRate(4, published: "2026-01-02", source: .init(provider: .frankfurter))
    let old = RateSnapshot(
      quotes: ["USD": daily, "BTC": live, "GBP": foreign], fetchedAt: now,
      dailyQuotes: legacy ? nil : ["USD": daily, "BTC": live, "GBP": foreign],
      dailyFetchedAt: now, checkedAt: now, fiatFetchedAt: now,
      supplementalFetchedAt: now, fiatQuotes: legacy ? nil : ["GBP": foreign],
      supplementalQuotes: legacy ? nil : ["USD": daily, "BTC": live])
    try RateCache(directory: directory).save(old)
    let store = RateStore(directory: directory, policy: .daily)
    let loaded = store.loadRates()
    #expect(loaded.quotes == ["USD": daily])
    #expect(loaded.dailyQuotes == ["USD": daily])
    #expect(loaded.fiatQuotes?.isEmpty == true)
    #expect(loaded.supplementalQuotes == ["USD": daily])
    #expect(loaded.checkedAt == nil)
    let saved = try store.saveBootstrapRates(old, now: now)
    #expect(saved.quotes == ["USD": daily])
    #expect(RateCache(directory: directory).load().quotes == ["USD": daily])
  }

  @Test func disablingRestoresExistingDailyCryptoAndCannotMergeLiveBackIn() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date()
    let daily = ExchangeRate(2, published: "2026-01-01", source: .init(provider: .fawaz))
    let live = ExchangeRate(
      3, published: "2026-01-02",
      source: .init(
        provider: .coinbase,
        observation: .exchangeRate), retrievedAt: now)
    let old = RateSnapshot(
      quotes: ["BTC": live], fetchedAt: now, dailyQuotes: ["BTC": daily],
      dailyFetchedAt: now, checkedAt: now)
    try RateCache(directory: directory).save(old)
    let store = RateStore(directory: directory, policy: .daily)
    #expect(store.loadRates().quotes["BTC"] == daily)
    let result = try await store.refreshRates(
      using: RateService(
        fiat: StubRateProvider(quotes: [:]), daily: StubRateProvider(quotes: ["BTC": daily]),
        crypto: StubRateProvider(quotes: ["BTC": live])), force: true, now: now)
    #expect(result.snapshot.quotes["BTC"]?.source.provider == .fawaz)
    #expect(store.loadRates().quotes["BTC"]?.source.provider == .fawaz)
  }

  @Test func disablingDoesNotAssignCoinbaseRetrievalTimeToDailyFallback() throws {
    let now = Date()
    let dailyTime = now.addingTimeInterval(-12 * 3600)
    let daily = ExchangeRate(
      2, published: "2026-01-01", source: .init(provider: .fawaz),
      cachedAt: dailyTime)
    let live = ExchangeRate(
      3, published: "2026-01-02",
      source: .init(
        provider: .coinbase,
        observation: .exchangeRate), retrievedAt: now)
    let saved = RateSnapshot(
      quotes: ["BTC": live], fetchedAt: now, dailyQuotes: ["BTC": daily],
      dailyFetchedAt: dailyTime, checkedAt: now, supplementalFetchedAt: dailyTime)
    let filtered = RateProviderPolicy.daily.filter(saved)
    #expect(filtered.quotes["BTC"] == daily)
    #expect(filtered.fetchedAt == dailyTime)
    #expect(filtered.dailyFetchedAt == dailyTime)
    #expect(filtered.checkedAt == nil)
    #expect(RateProviderPolicy.coinbaseEnhanced.filter(saved).fetchedAt == now)
    let unknown = ExchangeRate(2, published: "2026-01-01", source: .init(provider: .fawaz))
    let legacy = RateSnapshot(quotes: ["BTC": live, "USD": unknown], fetchedAt: now)
    #expect(RateProviderPolicy.daily.filter(legacy).fetchedAt == .distantPast)
  }

  @Test func dailyRefreshEarlyReturnUsesPolicyCadenceAndSanitizedSnapshot() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = PolicyHTTP()
    let now = Date()
    let store = RateStore(directory: directory, policy: .daily)
    let service = RateService(client: client)
    _ = try await store.refreshRates(using: service, now: now)
    _ = try await store.refreshRates(using: service, now: now.addingTimeInterval(1800))
    #expect(await client.urls.count == 1)
    _ = try await store.refreshRates(using: service, now: now.addingTimeInterval(21600))
    #expect(await client.urls.count == 2)
    #expect(RateProviderPolicy.coinbaseEnhanced.refreshInterval == 1800)
  }
}
