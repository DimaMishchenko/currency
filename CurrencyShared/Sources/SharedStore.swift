import Foundation
import RateCore

/// Storage shared between the app and widget extension.
public enum SharedStore {
  /// The App Group identifier used by both executables.
  public static let group = "group.com.dimasike.currency"
  /// The shared container directory, with a local fallback for tests and previews.
  public static var directory: URL {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Currency")
  }
  /// The shared rate-book store.
  public static var rates: DiskStore { DiskStore(directory: directory) }
  /// Loads the shared converter input.
  public static func input() -> InputState {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("input.json")),
      let input = try? JSONDecoder().decode(InputState.self, from: data)
    else { return InputState() }
    return input
  }
  /// Saves the shared converter input atomically.
  public static func save(_ input: InputState) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(input)
      .write(to: directory.appendingPathComponent("input.json"), options: .atomic)
  }
}
