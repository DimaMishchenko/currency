import Foundation

/// Coordinated rate persistence shared by independent app and widget processes.
public struct RateStore: Sendable {
  /// Directory shared by the hosts that exchange rate snapshots.
  public let directory: URL
  /// Creates a coordinated rate store in a host-supplied directory.
  public init(directory: URL) { self.directory = directory }
  private var rates: RateCache { RateCache(directory: directory) }
  /// Loads the latest valid snapshot from coordinated shared storage.
  public func loadRates() -> RateSnapshot { rates.load() }
  /// Refreshes shared rates, preserving newer results committed by another host.
  ///
  /// Network requests run outside file coordination. Unless forced, attempts are spaced
  /// thirty minutes apart. The final commit merges publication and observation metadata.
  public func refreshRates(
    using service: RateService, force: Bool = false, now: Date = .now,
    providerTimeout: Duration? = nil
  ) async throws -> RefreshResult {
    let previous = loadRates()
    guard
      force || now < (previous.checkedAt ?? .distantPast)
        || now.timeIntervalSince(previous.checkedAt ?? .distantPast) >= 1800
    else {
      return RefreshResult(snapshot: previous, warning: nil)
    }
    let result = await service.refresh(
      previous: previous, force: force, now: now, providerTimeout: providerTimeout)
    try Task.checkCancellation()
    return try coordinate("rates.json") {
      let current = loadRates()
      let merged = current.merging(result.snapshot)
      try rates.save(merged)
      return RefreshResult(
        snapshot: merged,
        warning: (current.checkedAt ?? .distantPast) > now ? nil : result.warning)
    }
  }

  func coordinate<Value>(_ filename: String, action: () throws -> Value) throws -> Value {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var coordinationError: NSError?
    var result: Result<Value, Error>?
    NSFileCoordinator()
      .coordinate(
        writingItemAt: directory.appendingPathComponent(filename), options: .forMerging,
        error: &coordinationError
      ) { _ in result = Result { try action() } }
    if let coordinationError { throw coordinationError }
    guard let result else { throw CocoaError(.fileWriteUnknown) }
    return try result.get()
  }
  /// Atomically merges a progressive refresh with quotes committed by another host.
  public func saveBootstrapRates(_ snapshot: RateSnapshot, now: Date = .now) throws -> RateSnapshot
  {
    try coordinate("rates.json") {
      // The incoming snapshot wins equal-attempt ties: it includes later provider deliveries.
      let saved = loadRates()
      let current = saved.hasValidFetchTimestamp(now: now) ? saved : RateSnapshot()
      let merged = snapshot.merging(current)
      try RateCache(directory: directory).save(merged)
      return merged
    }
  }
}
