import Foundation

/// An atomic disk-backed store for rate snapshots.
public struct RateCache: Sendable {
  /// The directory that contains the rate snapshot.
  private let directory: URL
  /// Creates a store rooted at a directory.
  public init(directory: URL) { self.directory = directory }
  /// Loads a valid saved rate snapshot or returns an empty one.
  public func load() -> RateSnapshot {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("rates.json")),
      let snapshot = try? JSONDecoder().decode(RateSnapshot.self, from: data),
      snapshot.quotes.values.allSatisfy({ $0.value > 0 && !$0.value.isNaN }),
      (snapshot.dailyQuotes ?? [:]).values.allSatisfy({ $0.value > 0 && !$0.value.isNaN })
    else { return RateSnapshot() }
    return snapshot
  }

  /// Saves a rate snapshot atomically.
  public func save(_ snapshot: RateSnapshot) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(snapshot)
      .write(to: directory.appendingPathComponent("rates.json"), options: .atomic)
  }
}
