import CoordinatedFiles
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
    (try? readWidgetInput(key: key, codes: codes, amount: amount))
      ?? WidgetInput(codes: codes, amount: amount)
  }

  private func readWidgetInput(key: String, codes: [String], amount: String) throws -> WidgetInput {
    let data = try FileCoordination.dataIfPresent(
      at: directory.appendingPathComponent(widgetFilename(key)))
    var input =
      try data.map { try JSONDecoder().decode(WidgetInput.self, from: $0) }
      ?? WidgetInput(codes: codes, amount: amount)
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
      var state = try readWidgetInput(key: key, codes: codes, amount: amount)
      mutation(&state)
      try JSONEncoder().encode(state)
        .write(to: directory.appendingPathComponent(filename), options: .atomic)
      return state
    }
  }

  func coordinate<Value>(_ filename: String, action: () throws -> Value) throws -> Value {
    try FileCoordination.write(at: directory.appendingPathComponent(filename), action)
  }
}
