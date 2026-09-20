import Foundation
import LocalCurrency

/// Coordinated persistence for conversionstore records shared by app and widget processes.
public struct ConversionStore: Sendable {
  /// Explicit directory supplied by the executable or an isolated test.
  public let directory: URL
  /// Creates a store without discovering a global container.
  public init(directory: URL) { self.directory = directory }
  private var local: LocalCurrencyStore { LocalCurrencyStore(directory: directory) }
  /// Loads the shared converter input.
  public func input() -> ConverterState {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("input.json")),
      var input = try? JSONDecoder().decode(ConverterState.self, from: data)
    else {
      var input = ConverterState()
      input.resolveLocalCurrency(local.widgetLocation(), status: local.widgetLocationStatus())
      return input
    }
    input.resolveLocalCurrency(local.widgetLocation(), status: local.widgetLocationStatus())
    return input
  }

  /// Applies an edit to freshly loaded input under a cross-process file coordination lock.
  @discardableResult
  public func updateInput(
    _ mutation: (inout ConverterState) throws -> Void
  ) throws -> ConverterState {
    try coordinate("input.json") {
      var state = input()
      try mutation(&state)
      try JSONEncoder().encode(state)
        .write(to: directory.appendingPathComponent("input.json"), options: .atomic)
      return state
    }
  }

  /// Applies a keypad command to the latest shared input.
  public func press(_ key: String) throws {
    try updateInput { $0.press(key) }
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
