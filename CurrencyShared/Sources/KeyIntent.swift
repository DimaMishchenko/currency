import AppIntents
import Foundation
import RateCore
import WidgetKit

/// Applies a keypad input from an interactive widget.
public struct KeyIntent: AppIntent {
  /// The localized intent title.
  public static let title: LocalizedStringResource = "Enter amount"
  /// The keypad command to apply.
  @Parameter(title: "Key") public var key: String
  /// Creates an empty intent for App Intents decoding.
  public init() {}
  /// Creates an intent for a keypad command.
  public init(_ key: String) { self.key = key }
  /// Coordinates and persists the keypad mutation.
  public func perform() async throws -> some IntentResult {
    // Coordinate the read/modify/write across widget extension processes.
    let url = SharedStore.directory.appendingPathComponent("input.json")
    var coordinationError: NSError?
    var writeError: Error?
    NSFileCoordinator()
      .coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { _ in
        var state = SharedStore.input(); state.press(key)
        do { try SharedStore.save(state) } catch { writeError = error }
      }
    if let error = coordinationError ?? writeError as NSError? { throw error }
    WidgetCenter.shared.reloadAllTimelines()
    return .result()
  }
}
