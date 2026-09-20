import Foundation
import Testing

@testable import ForegroundRefresh

@MainActor @Suite struct ForegroundRefreshTests {
  @Test func multipleScenesShareEachCadenceUntilLastSceneDeactivates() async {
    let rateSleeps = ControlledSuspension()
    let localSleeps = ControlledSuspension()
    let changes = Counter()
    var rates = 0
    var local = 0
    let refresh = ForegroundRefresh(
      dependencies: .init(
        refreshRates: { rates += 1 }, refreshLocalCurrency: { local += 1 },
        changed: { changes.increment() }, sleepRates: { try await rateSleeps.pause() },
        sleepLocalCurrency: { try await localSleeps.pause() }))
    let first = UUID()
    let second = UUID()
    refresh.setActive(true, sceneID: first)
    refresh.setActive(true, sceneID: first)
    refresh.setActive(true, sceneID: second)
    await rateSleeps.entries.wait(for: 1)
    await localSleeps.entries.wait(for: 1)
    #expect(rates == 1)
    #expect(local == 1)
    #expect(changes.value == 2)
    refresh.setActive(false, sceneID: first)
    rateSleeps.resume(1)
    await rateSleeps.entries.wait(for: 2)
    #expect(rates == 2)
    #expect(local == 1)
    #expect(changes.value == 3)
    refresh.setActive(false, sceneID: second)
    await rateSleeps.cancellations.wait(for: 1)
    await localSleeps.cancellations.wait(for: 1)
  }

  @Test func stoppedNoncooperativeRefreshCannotPublishOrClearReplacementWorker() async {
    let rates = ControlledSuspension(cancellable: false)
    let returned = Counter()
    let rateSleeps = ControlledSuspension()
    let localSleeps = ControlledSuspension()
    let changes = Counter()
    let refresh = ForegroundRefresh(
      dependencies: .init(
        refreshRates: {
          try? await rates.pause(); returned.increment()
        },
        refreshLocalCurrency: {}, changed: { changes.increment() },
        sleepRates: { try await rateSleeps.pause() },
        sleepLocalCurrency: { try await localSleeps.pause() }))
    let scene = UUID()
    refresh.setActive(true, sceneID: scene)
    await rates.entries.wait(for: 1)
    await localSleeps.entries.wait(for: 1)
    refresh.setActive(false, sceneID: scene)
    await localSleeps.cancellations.wait(for: 1)
    refresh.setActive(true, sceneID: scene)
    await rates.entries.wait(for: 2)
    await localSleeps.entries.wait(for: 2)
    let beforeOldResult = changes.value
    rates.resume(1)
    await returned.wait(for: 1)
    #expect(changes.value == beforeOldResult)
    refresh.setActive(true, sceneID: scene)
    rates.resume(2)
    await rateSleeps.entries.wait(for: 1)
    #expect(rates.entries.value == 2)
    #expect(changes.value == beforeOldResult + 1)
    refresh.setActive(false, sceneID: scene)
    await rateSleeps.cancellations.wait(for: 1)
    await localSleeps.cancellations.wait(for: 2)
  }

  @Test func cancelledLocationCannotNotifyAndDoesNotBlockRatePolling() async {
    let locations = ControlledSuspension(cancellable: false)
    let returned = Counter()
    let rateSleeps = ControlledSuspension()
    let localSleeps = ControlledSuspension()
    let changes = Counter()
    var rates = 0
    let refresh = ForegroundRefresh(
      dependencies: .init(
        refreshRates: { rates += 1 },
        refreshLocalCurrency: {
          try? await locations.pause(); returned.increment()
        },
        changed: { changes.increment() }, sleepRates: { try await rateSleeps.pause() },
        sleepLocalCurrency: { try await localSleeps.pause() }))
    let scene = UUID()
    refresh.setActive(true, sceneID: scene)
    await locations.entries.wait(for: 1)
    await rateSleeps.entries.wait(for: 1)
    rateSleeps.resume(1)
    await rateSleeps.entries.wait(for: 2)
    #expect(rates == 2)
    #expect(changes.value == 2)
    refresh.setActive(false, sceneID: scene)
    await rateSleeps.cancellations.wait(for: 1)
    locations.resume(1)
    await returned.wait(for: 1)
    #expect(changes.value == 2)
    refresh.setActive(true, sceneID: scene)
    await locations.entries.wait(for: 2)
    await rateSleeps.entries.wait(for: 3)
    locations.resume(2)
    await localSleeps.entries.wait(for: 1)
    #expect(rates == 3)
    #expect(changes.value == 4)
    refresh.setActive(false, sceneID: scene)
    await rateSleeps.cancellations.wait(for: 2)
    await localSleeps.cancellations.wait(for: 1)
  }
}

@MainActor private final class Counter {
  private(set) var value = 0
  private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

  func increment() {
    value += 1
    let ready = waiters.filter { $0.0 <= value }
    waiters.removeAll { $0.0 <= value }
    ready.forEach { $0.1.resume() }
  }

  func wait(for count: Int) async {
    guard value < count else { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
  }
}

/// Manually controlled work; cancellation can deliberately be ignored to exercise stale results.
@MainActor private final class ControlledSuspension {
  let entries = Counter()
  let cancellations = Counter()
  private let cancellable: Bool
  private var pending: [Int: CheckedContinuation<Void, Error>] = [:]

  init(cancellable: Bool = true) { self.cancellable = cancellable }

  func pause() async throws {
    let id = entries.value + 1
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        pending[id] = continuation
        entries.increment()
        if cancellable && Task.isCancelled { cancel(id) }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        guard let self, self.cancellable else { return }
        self.cancel(id)
      }
    }
  }

  func resume(_ id: Int) { pending.removeValue(forKey: id)?.resume() }

  private func cancel(_ id: Int) {
    guard let continuation = pending.removeValue(forKey: id) else { return }
    continuation.resume(throwing: CancellationError())
    cancellations.increment()
  }
}
