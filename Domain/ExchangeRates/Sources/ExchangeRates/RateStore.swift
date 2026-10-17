import CoordinatedFiles
import Foundation

/// Coordinated rate persistence shared by independent app and widget processes.
public struct RateStore: Sendable {
  /// Directory shared by the hosts that exchange rate snapshots.
  public let directory: URL
  /// Creates a coordinated rate store in a host-supplied directory.
  public init(directory: URL) {
    self.directory = directory
  }
  private var rates: RateCache { RateCache(directory: directory) }
  /// Loads the latest valid snapshot from coordinated shared storage.
  public func loadRates() -> RateSnapshot { rates.load().aligningCoinMetricsQuotes() }
  /// Refreshes shared rates, preserving newer results committed by another host.
  ///
  /// Network requests run outside file coordination. Unless forced, attempts are spaced
  /// by one minute, with a ten-second minimum for manual refresh. Concurrent hosts
  /// reuse the owning refresh while its bounded lease is active.
  public func refreshRates(
    using service: RateService, force: Bool = false, now: Date = .now,
    providerTimeout: Duration? = nil
  ) async throws -> RefreshResult {
    let owner = UUID()
    let started = ContinuousClock.now
    var joinedRefresh = false
    while true {
      try Task.checkCancellation()
      let acquired = try coordinate("rate-refresh.json") { () -> Bool in
        var state = try refreshState()
        let previous = loadRates()
        if let lease = state.lease, lease.expires > .now { return false }
        if joinedRefresh { return false }
        let lastAttempt = max(state.attemptedAt ?? .distantPast, previous.checkedAt ?? .distantPast)
        let interval = force ? RateRefreshCadence.manualMinimum : RateRefreshCadence.foreground
        if now >= lastAttempt, now.timeIntervalSince(lastAttempt) < interval { return false }
        state.lease = RefreshLease(owner: owner, expires: Date.now.addingTimeInterval(120))
        state.attemptedAt = now
        try saveRefreshState(state)
        return true
      }
      if acquired { break }
      let active = try coordinate("rate-refresh.json") {
        try refreshState().lease.map { $0.expires > .now } ?? false
      }
      if !active { return RefreshResult(snapshot: loadRates(), warning: nil) }
      joinedRefresh = true
      if let providerTimeout, started.duration(to: .now) >= providerTimeout {
        return RefreshResult(snapshot: loadRates(), warning: nil)
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    defer {
      try? coordinate("rate-refresh.json") {
        var state = try refreshState()
        if state.lease?.owner == owner {
          state.lease = nil
          try saveRefreshState(state)
        }
      }
    }
    try Task.checkCancellation()
    let result = await service.refresh(
      previous: loadRates(), force: force, now: now, providerTimeout: providerTimeout)
    try Task.checkCancellation()
    return try coordinate("rate-refresh.json") {
      guard try refreshState().lease?.owner == owner else {
        return RefreshResult(snapshot: loadRates(), warning: nil)
      }
      return try coordinate("rates.json") {
        let current = loadRates()
        let merged = current.merging(result.snapshot).aligningCoinMetricsQuotes()
        try rates.save(merged)
        return RefreshResult(
          snapshot: merged,
          warning: (current.checkedAt ?? .distantPast) > now ? nil : result.warning)
      }
    }
  }

  private func refreshState() throws -> RefreshState {
    try FileCoordination.dataIfPresent(at: directory.appendingPathComponent("rate-refresh.json"))
      .map { try JSONDecoder().decode(RefreshState.self, from: $0) } ?? RefreshState()
  }

  private func saveRefreshState(_ state: RefreshState) throws {
    try JSONEncoder().encode(state)
      .write(to: directory.appendingPathComponent("rate-refresh.json"), options: .atomic)
  }

  struct RefreshState: Codable {
    var lease: RefreshLease?
    var attemptedAt: Date?
  }

  struct RefreshLease: Codable {
    let owner: UUID
    let expires: Date
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
      let merged = snapshot.merging(current).aligningCoinMetricsQuotes()
      try RateCache(directory: directory).save(merged)
      return merged
    }
  }
}

/// Shared current-quote cadence for foreground hosts and explicit user refreshes.
public enum RateRefreshCadence {
  /// Minimum interval between automatic current-quote refresh attempts.
  public static let foreground: TimeInterval = 60
  /// Minimum interval between explicit refresh attempts, including failed attempts.
  public static let manualMinimum: TimeInterval = 10
}
