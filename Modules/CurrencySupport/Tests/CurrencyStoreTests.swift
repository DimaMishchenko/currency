import CurrencySupport
import ExchangeRates
import Foundation
import Testing

private struct ImmediateProvider: RateProvider {
  let value: Decimal
  func fetch() async throws -> [String: ExchangeRate] {
    ["USD": ExchangeRate(value, published: "2026-01-02", source: .init(provider: .ecb))]
  }
}

private struct FailingProvider: RateProvider {
  func fetch() async throws -> [String: ExchangeRate] {
    throw CocoaError(.fileReadUnknown)
  }
}

private actor SuspendedProvider: RateProvider {
  private var pending: CheckedContinuation<[String: ExchangeRate], Error>?
  private var started: CheckedContinuation<Void, Never>?
  func fetch() async throws -> [String: ExchangeRate] {
    try await withCheckedThrowingContinuation {
      pending = $0
      started?.resume()
      started = nil
    }
  }

  func waitUntilStarted() async {
    if pending != nil { return }
    await withCheckedContinuation { started = $0 }
  }

  func fail() {
    pending?.resume(throwing: CocoaError(.fileReadUnknown))
    pending = nil
  }
}

private actor SlowWidgetProvider: RateProvider {
  private(set) var cancelled = false
  func fetch() async throws -> [String: ExchangeRate] {
    do {
      try await Task.sleep(for: .seconds(30))
      return [:]
    } catch {
      cancelled = true
      throw error
    }
  }
}

@Suite struct CurrencyStoreTests {
  @Test func interleavedHostsPreserveAmountAndSelectionEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = CurrencyStore(directory: directory)
    let widget = CurrencyStore(directory: directory)
    let displayed = app.input()
    try widget.press("AC")
    try widget.press("4")
    try widget.press("2")
    let updated = try app.updateInput { $0.setDestinations($0.destinations + ["PLN"]) }
    #expect(displayed.amount == "1")
    #expect(updated.amount == "42")
    #expect(widget.input().destinations.contains("PLN"))
    try app.updateInput { $0.moveDestinations(["GBP"], before: "USD") }
    #expect(widget.input().destinations.first == "GBP")
    #expect(widget.input().destinations.contains("PLN"))
  }

  @Test func staleFailedRefreshCannotOverwriteNewerHostCommit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let suspended = SuspendedProvider()
    let service = RateService(fiat: suspended, daily: FailingProvider(), crypto: nil)
    let task = Task {
      try await store.refreshRates(
        using: service, force: true, now: Date(timeIntervalSince1970: 100))
    }
    await suspended.waitUntilStarted()
    let newService = RateService(
      fiat: ImmediateProvider(value: 2), daily: ImmediateProvider(value: 2), crypto: nil)
    _ = try await store.refreshRates(
      using: newService, force: true, now: Date(timeIntervalSince1970: 200))
    await suspended.fail()
    let result = try await task.value
    #expect(result.warning == nil)
    #expect(result.snapshot.quotes["USD"]?.value == 2)
    #expect(store.loadRates().quotes["USD"]?.value == 2)
    #expect(store.loadRates().checkedAt == Date(timeIntervalSince1970: 200))
  }
  @Test func widgetRefreshDeadlineCancelsSlowProviderAndPreservesCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let cached = RateSnapshot(quotes: [
      "USD": ExchangeRate(2, published: "2026-01-02", source: .init(provider: .ecb))
    ])
    try RateCache(directory: directory).save(cached)
    let slow = SlowWidgetProvider()
    let started = ContinuousClock.now
    let result = try await store.refreshRates(
      using: RateService(fiat: slow, daily: FailingProvider(), crypto: nil),
      providerTimeout: .milliseconds(30))
    #expect(result.warning == .dailyRatesUnavailable)
    #expect(started.duration(to: .now) < .seconds(2))
    #expect(await slow.cancelled)
    #expect(store.loadRates().quotes["USD"]?.value == 2)
    #expect(store.loadRates().checkedAt != nil)
  }

  @Test func widgetRefreshReturnsFastResultWithoutWaitingForDeadline() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let started = ContinuousClock.now
    let result = try await store.refreshRates(
      using: RateService(fiat: ImmediateProvider(value: 3), daily: FailingProvider(), crypto: nil),
      providerTimeout: .seconds(30))
    #expect(result.snapshot.quotes["USD"]?.value == 3)
    #expect(started.duration(to: .now) < .seconds(2))
    #expect(store.loadRates().quotes["USD"]?.value == 3)
  }

  @Test func widgetRefreshKeepsFastFiatWhenCryptoTimesOut() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let slow = SlowWidgetProvider()
    let result = try await store.refreshRates(
      using: RateService(fiat: ImmediateProvider(value: 3), daily: FailingProvider(), crypto: slow),
      providerTimeout: .milliseconds(30))
    #expect(result.warning == .partialCryptoFallback)
    #expect(await slow.cancelled)
    #expect(store.loadRates().quotes["USD"]?.value == 3)
  }

}
