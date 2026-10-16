import Foundation
import Testing

@testable import ExchangeRates

private actor SharedQuoteProvider: RateProvider {
  private(set) var calls = 0
  private(set) var cancelled = false
  let delay: Duration
  init(delay: Duration = .zero) { self.delay = delay }

  func fetch() async throws -> [String: ExchangeRate] {
    calls += 1
    do { try await Task.sleep(for: delay) } catch {
      cancelled = true
      throw error
    }
    return [
      "BTC": ExchangeRate(
        Decimal(calls), published: "2026-10-16", source: .init(provider: .coinMetrics),
        observedAt: Date(timeIntervalSince1970: Double(calls)))
    ]
  }
}

@Suite struct SharedRateRefreshTests {
  private func service(_ provider: SharedQuoteProvider) -> RateService {
    RateService(
      fiat: StubRateProvider(quotes: [:]), daily: StubRateProvider(quotes: [:]), crypto: provider)
  }

  @Test func independentlyConstructedHostsCoalesceOneRefreshAndReadSameQuote() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = SharedQuoteProvider(delay: .milliseconds(150))
    let first = RateStore(directory: directory)
    let second = RateStore(directory: directory)
    async let app = first.refreshRates(using: service(provider), force: true)
    async let widget = second.refreshRates(using: service(provider), force: true)
    let (appResult, widgetResult) = try await (app, widget)
    #expect(await provider.calls == 1)
    #expect(appResult.snapshot.quotes["BTC"] == widgetResult.snapshot.quotes["BTC"])
    #expect(first.loadRates().quotes == second.loadRates().quotes)
  }

  @Test func automaticRefreshUsesMinuteCadenceAndManualRefreshUsesTenSeconds() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = SharedQuoteProvider()
    let now = Date.now
    for (offset, force, expected) in [
      (0.0, false, 1), (59, false, 1), (60, false, 2),
      (69, true, 2), (70, true, 3)
    ] {
      _ = try await RateStore(directory: directory)
        .refreshRates(
          using: service(provider), force: force, now: now.addingTimeInterval(offset))
      #expect(await provider.calls == expected)
    }
  }

  @Test func expiredLeaseRecoversAndMalformedLeasePreventsNetwork() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("rate-refresh.json")
    let state = RateStore.RefreshState(lease: .init(owner: UUID(), expires: .distantPast))
    try JSONEncoder().encode(state).write(to: url)
    let provider = SharedQuoteProvider()
    _ = try await RateStore(directory: directory).refreshRates(using: service(provider))
    #expect(await provider.calls == 1)
    try Data("corrupt".utf8).write(to: url)
    await #expect(throws: (any Error).self) {
      _ = try await RateStore(directory: directory)
        .refreshRates(using: service(provider), force: true)
    }
    #expect(await provider.calls == 1)
  }

  @Test func failedRefreshCannotPersistRejectedFutureCachedObservation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date.now
    let daily = ExchangeRate(1, published: "2026-10-16", source: .init(provider: .fawaz))
    let future = ExchangeRate(
      9, published: "2026-10-16", source: .init(provider: .coinMetrics),
      observedAt: now.addingTimeInterval(60))
    try RateCache(directory: directory)
      .save(
        RateSnapshot(
          quotes: ["BTC": future], fetchedAt: now.addingTimeInterval(-60),
          dailyQuotes: ["BTC": daily], checkedAt: now.addingTimeInterval(-60)))
    let store = RateStore(directory: directory)
    let result = try await store.refreshRates(
      using: RateService(
        fiat: StubRateProvider(quotes: nil), daily: StubRateProvider(quotes: nil),
        crypto: StubRateProvider(quotes: nil)), now: now)
    #expect(result.snapshot.quotes["BTC"] == daily)
    #expect(store.loadRates().quotes["BTC"] == daily)
  }

  @Test func waitingWidgetDeadlineLeavesOtherHostLeaseIntact() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("rate-refresh.json")
    let owner = UUID()
    let state = RateStore.RefreshState(
      lease: .init(owner: owner, expires: Date.now.addingTimeInterval(30)))
    try JSONEncoder().encode(state).write(to: url)
    let provider = SharedQuoteProvider()
    let start = ContinuousClock.now
    _ = try await RateStore(directory: directory)
      .refreshRates(
        using: service(provider), providerTimeout: .milliseconds(30))
    #expect(start.duration(to: .now) < .seconds(1))
    #expect(await provider.calls == 0)
    let preserved = try JSONDecoder()
      .decode(RateStore.RefreshState.self, from: Data(contentsOf: url))
    #expect(preserved.lease?.owner == owner)
  }

  @Test func cancelledOldOwnerCannotReleaseSuccessorLease() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = SharedQuoteProvider(delay: .seconds(30))
    let store = RateStore(directory: directory)
    let refresh = Task { try await store.refreshRates(using: service(provider)) }
    for _ in 0..<100 {
      if await provider.calls == 1 { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let successor = UUID()
    let url = directory.appendingPathComponent("rate-refresh.json")
    try store.coordinate("rate-refresh.json") {
      try JSONEncoder()
        .encode(
          RateStore.RefreshState(
            lease: .init(owner: successor, expires: Date.now.addingTimeInterval(30)))
        )
        .write(to: url, options: .atomic)
    }
    refresh.cancel()
    await #expect(throws: CancellationError.self) { try await refresh.value }
    let preserved = try JSONDecoder()
      .decode(RateStore.RefreshState.self, from: Data(contentsOf: url))
    #expect(preserved.lease?.owner == successor)
    #expect(store.loadRates().quotes.isEmpty)
  }

  @Test func cancellationReleasesOwnedLeaseAndDoesNotCommit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = SharedQuoteProvider(delay: .seconds(30))
    let store = RateStore(directory: directory)
    let refresh = Task { try await store.refreshRates(using: service(provider)) }
    for _ in 0..<100 {
      if await provider.calls == 1 { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await provider.calls == 1)
    refresh.cancel()
    await #expect(throws: CancellationError.self) { try await refresh.value }
    #expect(await provider.cancelled)
    #expect(store.loadRates().quotes.isEmpty)
    let state = try JSONDecoder()
      .decode(
        RateStore.RefreshState.self,
        from: Data(contentsOf: directory.appendingPathComponent("rate-refresh.json")))
    #expect(state.lease == nil)
  }
}
