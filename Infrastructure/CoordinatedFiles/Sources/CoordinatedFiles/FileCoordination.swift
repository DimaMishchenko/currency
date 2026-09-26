import Foundation

/// Foundation file coordination shared by stores in separate executables.
/// Record formats, recovery, and lock ordering remain with each owning store.
public enum FileCoordination {
  /// Runs a synchronous write against one coordinated URL.
  public static func write<Value>(at url: URL, _ action: () throws -> Value) throws -> Value {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var coordinationError: NSError?
    var result: Result<Value, Error>?
    NSFileCoordinator()
      .coordinate(
        writingItemAt: url, options: .forMerging,
        error: &coordinationError
      ) { _ in result = Result { try action() } }
    if let coordinationError { throw coordinationError }
    guard let result else { throw CocoaError(.fileWriteUnknown) }
    return try result.get()
  }

  /// Only an absent file is empty; unreadable records must never become mutation defaults.
  public static func dataIfPresent(at url: URL) throws -> Data? {
    do { return try Data(contentsOf: url) } catch let error as CocoaError {
      guard error.code == .fileReadNoSuchFile else { throw error }
      return nil
    }
  }
}
