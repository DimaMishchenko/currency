import CryptoKit
import Foundation

/// Coordinated persistence for widgetstore records shared by app and widget processes.
public struct WidgetStore: Sendable {
  /// Explicit directory supplied by the executable or an isolated test.
  public let directory: URL
  /// Creates a store without discovering a global container.
  public init(directory: URL) { self.directory = directory }
  private func widgetFilename(_ key: String) -> String {
    "widget-" + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
      + ".json"
  }

  /// Loads a configuration-specific input, recovering safely from missing or incompatible data.
  public func widgetInput(
    key: String, codes: [String], amount: String = "1"
  ) -> WidgetInput {
    guard
      let data = try? Data(
        contentsOf: directory.appendingPathComponent(widgetFilename(key))),
      var input = try? JSONDecoder().decode(WidgetInput.self, from: data)
    else { return WidgetInput(codes: codes, amount: amount) }
    input.reconcile(codes: codes)
    return input
  }

  /// Coordinates a widget mutation against the latest persisted state across processes.
  @discardableResult
  public func updateWidgetInput(
    key: String, codes: [String], amount: String = "1",
    mutation: (inout WidgetInput) -> Void
  ) throws -> WidgetInput {
    let filename = widgetFilename(key)
    return try coordinate(filename) {
      var state = widgetInput(key: key, codes: codes, amount: amount)
      mutation(&state)
      try JSONEncoder().encode(state)
        .write(to: directory.appendingPathComponent(filename), options: .atomic)
      return state
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
}
