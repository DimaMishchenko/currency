import CoordinatedFiles
import Foundation

/// Coordinated rate persistence shared by independent app and widget processes.
public struct RateStore: Sendable {
  /// Directory shared by the hosts that exchange rate snapshots.
  public let directory: URL
  private let policy: RateProviderPolicy?
  /// Creates a coordinated rate store in a host-supplied directory.
  /// A nil policy preserves injected provider provenance and a thirty-minute refresh cadence.
  public init(directory: URL, policy: RateProviderPolicy? = nil) {
    self.directory = directory
    self.policy = policy
  }
  private var rates: RateCache { RateCache(directory: directory) }
  /// Loads the latest valid snapshot from coordinated shared storage.
  public func loadRates() -> RateSnapshot { filter(rates.load()) }
  /// Refreshes shared rates, preserving newer results committed by another host.
  ///
  /// Network requests run outside file coordination. Unless forced, attempts are spaced
  /// according to the selected provider cadence. The final commit merges publication and observation metadata.
  public func refreshRates(
    using service: RateService, force: Bool = false, now: Date = .now,
    providerTimeout: Duration? = nil
  ) async throws -> RefreshResult {
    let previous = loadRates()
    guard
      force || now < (previous.checkedAt ?? .distantPast)
        || now.timeIntervalSince(previous.checkedAt ?? .distantPast)
          >= (policy?.refreshInterval ?? 1800)
    else {
      return RefreshResult(snapshot: previous, warning: nil)
    }
    let result = await service.refresh(
      previous: previous, force: force, now: now, providerTimeout: providerTimeout)
    try Task.checkCancellation()
    return try coordinate("rates.json") {
      let current = loadRates()
      let merged = filter(current.merging(filter(result.snapshot)))
      try rates.save(merged)
      return RefreshResult(
        snapshot: merged,
        warning: (current.checkedAt ?? .distantPast) > now ? nil : result.warning)
    }
  }

  private func filter(_ snapshot: RateSnapshot) -> RateSnapshot {
    policy?.filter(snapshot) ?? snapshot
  }

  func coordinate<Value>(_ filename: String, action: () throws -> Value) throws -> Value {
    try FileCoordination.write(at: directory.appendingPathComponent(filename), action)
  }
  /// Atomically merges a progressive refresh with quotes committed by another host.
  public func saveBootstrapRates(_ snapshot: RateSnapshot, now: Date = .now) throws -> RateSnapshot
  {
    try coordinate("rates.json") {
      let saved = loadRates()
      let current = saved.hasValidFetchTimestamp(now: now) ? saved : RateSnapshot()
      let merged = filter(filter(snapshot).merging(current))
      try RateCache(directory: directory).save(merged)
      return merged
    }
  }
}
