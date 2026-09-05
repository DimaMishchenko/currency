import ExchangeRates
import Foundation

/// Storage shared between the app and widget extension.
public struct CurrencyStore: Sendable {
  /// The App Group store used by the shipping app and widgets.
  public static var shared: CurrencyStore { CurrencyStore(directory: sharedDirectory) }

  /// The location shared by input, rate snapshots, and historical caches.
  public let directory: URL

  /// Creates an isolated store, suitable for previews, tests, or another app container.
  public init(directory: URL) { self.directory = directory }

  /// The App Group identifier used by both executables.
  private static let group = "group.com.dimasike.currency"
  /// The shared container directory, with a local fallback for tests and previews.
  private static var sharedDirectory: URL {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Currency")
  }
  private var rates: RateCache { RateCache(directory: directory) }

  /// Loads the latest shared rate snapshot.
  public func loadRates() -> RateSnapshot { rates.load() }

  /// Loads the shared converter input.
  public func input() -> ConverterState {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("input.json")),
      let input = try? JSONDecoder().decode(ConverterState.self, from: data)
    else { return ConverterState() }
    return input
  }

  /// Applies an edit to freshly loaded input under a cross-process file coordination lock.
  @discardableResult
  public func updateInput(_ mutation: (inout ConverterState) -> Void) throws -> ConverterState {
    try coordinate("input.json") {
      var state = input()
      mutation(&state)
      try JSONEncoder().encode(state)
        .write(to: directory.appendingPathComponent("input.json"), options: .atomic)
      return state
    }
  }

  /// Applies a keypad command to the latest shared input.
  public func press(_ key: String) throws {
    try updateInput { $0.press(key) }
  }

  /// Refreshes shared rates, preserving newer results committed by another host.
  ///
  /// Network requests run outside file coordination. Unless forced, attempts are spaced
  /// thirty minutes apart. The final commit merges publication and observation metadata.
  public func refreshRates(
    using service: RateService, force: Bool = false, now: Date = .now
  ) async throws -> RefreshResult {
    let previous = loadRates()
    guard force || now.timeIntervalSince(previous.checkedAt ?? .distantPast) >= 1800 else {
      return RefreshResult(snapshot: previous, warning: nil)
    }
    let result = await service.refresh(previous: previous, force: force, now: now)
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

  private func coordinate<Value>(_ filename: String, action: () throws -> Value) throws -> Value {
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
}
