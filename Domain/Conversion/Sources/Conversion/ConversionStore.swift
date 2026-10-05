import CoordinatedFiles
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
    (try? readInput()) ?? resolved(ConverterState())
  }

  /// Loads confirmed input, defaulting only when its record is absent.
  public func readInput() throws -> ConverterState {
    let data = try FileCoordination.dataIfPresent(
      at: directory.appendingPathComponent("input.json"))
    let input = try data.map { try JSONDecoder().decode(ConverterState.self, from: $0) }
    return resolved(input ?? ConverterState())
  }

  private func resolved(_ value: ConverterState) -> ConverterState {
    var input = value
    input.resolveLocalCurrency(local.widgetLocation(), status: local.widgetLocationStatus())
    return input
  }

  /// Applies an edit to freshly loaded input under a cross-process file coordination lock.
  @discardableResult
  public func updateInput(
    _ mutation: (inout ConverterState) throws -> Void
  ) throws -> ConverterState {
    try coordinate("input.json") {
      var state = try readInput()
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
    try FileCoordination.write(at: directory.appendingPathComponent(filename), action)
  }
}
