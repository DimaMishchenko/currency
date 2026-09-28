import Foundation

/// App-local persistence for converter discovery progress.
@MainActor
public struct HomeDiscoveryStore {
  private let defaults: UserDefaults
  private let key = "homeDiscoveryProgress"

  /// Uses the supplied defaults domain so tests and hosts can isolate progress.
  public init(defaults: UserDefaults) { self.defaults = defaults }

  /// Restores saved progress or an empty state for a new installation.
  public func load() -> HomeDiscoveryProgress {
    guard let data = defaults.data(forKey: key),
      let progress = try? JSONDecoder().decode(HomeDiscoveryProgress.self, from: data)
    else { return HomeDiscoveryProgress() }
    return progress
  }

  /// Persists a completed learning transition.
  public func save(_ progress: HomeDiscoveryProgress) {
    guard let data = try? JSONEncoder().encode(progress) else { return }
    defaults.set(data, forKey: key)
  }
}
