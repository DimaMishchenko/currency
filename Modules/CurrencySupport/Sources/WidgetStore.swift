import CryptoKit
import Foundation

extension CurrencyStore {
  private func widgetFilename(_ key: String) -> String {
    "widget-" + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
      + ".json"
  }

  /// Loads a configuration-specific input, recovering safely from missing or incompatible data.
  public func widgetInput(key: String, codes: [String], amount: String = "1") -> WidgetInput {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent(widgetFilename(key))),
      let input = try? JSONDecoder().decode(WidgetInput.self, from: data),
      input.codes == WidgetInput(codes: codes).codes
    else { return WidgetInput(codes: codes, amount: amount) }
    return input
  }

  /// Coordinates a widget mutation against the latest persisted state across processes.
  @discardableResult
  public func updateWidgetInput(
    key: String, codes: [String], amount: String = "1", mutation: (inout WidgetInput) -> Void
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

  /// Loads the coarse location observation; freshness is evaluated by the consumer.
  public func widgetLocation() -> WidgetLocation? {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("widget-location.json"))
    else { return nil }
    return try? JSONDecoder().decode(WidgetLocation.self, from: data)
  }

  /// Atomically saves or removes the opt-in coarse location cache.
  public func saveWidgetLocation(_ location: WidgetLocation?) throws {
    try coordinate("widget-location.json") {
      let url = directory.appendingPathComponent("widget-location.json")
      if let location {
        try JSONEncoder().encode(location).write(to: url, options: .atomic)
      } else if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    }
  }
}
