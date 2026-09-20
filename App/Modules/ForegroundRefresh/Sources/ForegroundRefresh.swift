import Foundation

/// One app-wide automatic lifetime regardless of the number of active scenes.
@MainActor
public final class ForegroundRefresh {
  /// Domain operations and independently controlled polling cadences.
  public struct Dependencies: Sendable {
    /// Refreshes rates using the domain's freshness and commit policy.
    public var refreshRates: @MainActor @Sendable () async -> Void
    /// Refreshes authorized Local observations without prompting.
    public var refreshLocalCurrency: @MainActor @Sendable () async -> Void
    /// Notifies observers after a current operation returns.
    public var changed: @MainActor @Sendable () -> Void
    /// Preserves the app's one-minute rate polling cadence.
    public var sleepRates: @MainActor @Sendable () async throws -> Void
    /// Preserves the app's five-minute Local polling cadence.
    public var sleepLocalCurrency: @MainActor @Sendable () async throws -> Void

    /// Supplies required operations and controlled or live polling intervals.
    public init(
      refreshRates: @escaping @MainActor @Sendable () async -> Void,
      refreshLocalCurrency: @escaping @MainActor @Sendable () async -> Void,
      changed: @escaping @MainActor @Sendable () -> Void,
      sleepRates: @escaping @MainActor @Sendable () async throws -> Void = {
        try await Task.sleep(for: .seconds(60))
      },
      sleepLocalCurrency: @escaping @MainActor @Sendable () async throws -> Void = {
        try await Task.sleep(for: .seconds(300))
      }
    ) {
      self.refreshRates = refreshRates
      self.refreshLocalCurrency = refreshLocalCurrency
      self.changed = changed
      self.sleepRates = sleepRates
      self.sleepLocalCurrency = sleepLocalCurrency
    }
  }

  private let dependencies: Dependencies
  private var scenes: Set<UUID> = []
  private var worker: Task<Void, Never>?
  private var generation = UUID()

  /// Creates an idle coordinator; the first active scene starts both polling loops.
  public init(dependencies: Dependencies) { self.dependencies = dependencies }

  /// Cancels the shared lifetime only after its last active scene leaves.
  public func setActive(_ active: Bool, sceneID: UUID) {
    if active { scenes.insert(sceneID) } else { scenes.remove(sceneID) }
    if scenes.isEmpty {
      generation = UUID()
      worker?.cancel()
      worker = nil
    } else if worker == nil {
      let id = UUID()
      generation = id
      worker = Task { [weak self, dependencies] in
        async let rates: Void = Self.poll(
          refresh: dependencies.refreshRates, sleep: dependencies.sleepRates,
          changed: dependencies.changed)
        async let local: Void = Self.poll(
          refresh: dependencies.refreshLocalCurrency, sleep: dependencies.sleepLocalCurrency,
          changed: dependencies.changed)
        _ = await (rates, local)
        if self?.generation == id { self?.worker = nil }
      }
    }
  }

  private static func poll(
    refresh: @MainActor @Sendable () async -> Void,
    sleep: @MainActor @Sendable () async throws -> Void,
    changed: @MainActor @Sendable () -> Void
  ) async {
    while !Task.isCancelled {
      await refresh()
      guard !Task.isCancelled else { break }
      changed()
      do { try await sleep() } catch { break }
    }
  }
}
