import Foundation
import Testing

@testable import ExchangeRates

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

  func succeed(_ value: Decimal) {
    pending?
      .resume(returning: [
        "USD": ExchangeRate(value, published: "2026-01-02", source: .init(provider: .ecb))
      ])
    pending = nil
  }
}

private actor ManualDeadline {
  private var pending: [UUID: CheckedContinuation<Void, Error>] = [:]
  private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var released = false
  private(set) var startedCount = 0
  private(set) var cancelledCount = 0

  func sleep(for _: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler(
      operation: { try await waitForRelease(id: id) },
      onCancel: { Task { await self.cancel(id) } })
  }

  private func waitForRelease(id: UUID) async throws {
    try await withCheckedThrowingContinuation { (sleeper: CheckedContinuation<Void, Error>) in
      startedCount += 1
      let ready = startWaiters.filter { startedCount >= $0.0 }
      startWaiters.removeAll { startedCount >= $0.0 }
      for (_, waiter) in ready { waiter.resume() }
      if Task.isCancelled {
        cancelledCount += 1
        sleeper.resume(throwing: CancellationError())
      } else if released {
        sleeper.resume()
      } else {
        pending[id] = sleeper
      }
    }
  }

  func waitUntilStarted(_ count: Int) async {
    if startedCount >= count { return }
    await withCheckedContinuation { startWaiters.append((count, $0)) }
  }

  func release() {
    released = true
    let sleepers = pending.values
    pending.removeAll()
    for sleeper in sleepers { sleeper.resume() }
  }

  private func cancel(_ id: UUID) {
    guard let sleeper = pending.removeValue(forKey: id) else { return }
    cancelledCount += 1
    sleeper.resume(throwing: CancellationError())
  }
}

private actor SlowWidgetProvider: RateProvider {
  private(set) var cancelled = false
  private var started = false
  private var startWaiter: CheckedContinuation<Void, Never>?
  func fetch() async throws -> [String: ExchangeRate] {
    started = true
    startWaiter?.resume()
    startWaiter = nil
    do {
      try await Task.sleep(for: .seconds(30))
      return [:]
    } catch {
      cancelled = true
      throw error
    }
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { startWaiter = $0 }
  }
}

@Suite struct RateStoreTests {
  @Test func staleFailedRefreshCannotOverwriteNewerHostCommit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RateStore(directory: directory)
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
    let store = RateStore(directory: directory)
    let cached = RateSnapshot(quotes: [
      "USD": ExchangeRate(2, published: "2026-01-02", source: .init(provider: .ecb))
    ])
    try RateCache(directory: directory).save(cached)
    let slow = SlowWidgetProvider()
    let deadline = ManualDeadline()
    let service = RateService(
      fiat: slow, daily: FailingProvider(), crypto: nil,
      sleep: { try await deadline.sleep(for: $0) })
    let refresh = Task {
      try await store.refreshRates(using: service, providerTimeout: .seconds(30))
    }
    await slow.waitUntilStarted()
    await deadline.waitUntilStarted(1)
    await deadline.release()
    let result = try await refresh.value
    #expect(result.warning == .dailyRatesUnavailable)
    #expect(await slow.cancelled)
    #expect(store.loadRates().quotes["USD"]?.value == 2)
    #expect(store.loadRates().checkedAt != nil)
  }

  @Test func widgetRefreshReturnsFastResultWithoutWaitingForDeadline() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RateStore(directory: directory)
    let fiat = SuspendedProvider()
    let daily = SuspendedProvider()
    let deadline = ManualDeadline()
    let service = RateService(
      fiat: fiat, daily: daily, crypto: nil,
      sleep: { try await deadline.sleep(for: $0) })
    let refresh = Task {
      try await store.refreshRates(using: service, providerTimeout: .seconds(30))
    }
    await fiat.waitUntilStarted()
    await daily.waitUntilStarted()
    await deadline.waitUntilStarted(2)
    await fiat.succeed(3)
    await daily.succeed(3)
    let result = try await refresh.value
    #expect(result.snapshot.quotes["USD"]?.value == 3)
    #expect(await deadline.cancelledCount == 2)
    #expect(store.loadRates().quotes["USD"]?.value == 3)
  }

  @Test func widgetRefreshKeepsFastFiatWhenCryptoTimesOut() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RateStore(directory: directory)
    let slow = SlowWidgetProvider()
    let result = try await store.refreshRates(
      using: RateService(fiat: ImmediateProvider(value: 3), daily: FailingProvider(), crypto: slow),
      providerTimeout: .milliseconds(30))
    #expect(result.warning == .partialCryptoFallback)
    #expect(await slow.cancelled)
    #expect(store.loadRates().quotes["USD"]?.value == 3)
  }

}
