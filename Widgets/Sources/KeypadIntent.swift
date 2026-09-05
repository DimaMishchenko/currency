import AppIntents
import CurrencySupport
import Foundation
import WidgetKit

/// Applies a keypad input from an interactive widget.
struct KeypadIntent: AppIntent {
  /// The localized intent title.
  // App Intents metadata extraction requires a literal initializer, not a generated getter.
  static let title = LocalizedStringResource(
    "enterAmount", defaultValue: "Enter amount", table: "Widgets")
  /// The keypad command to apply.
  @Parameter(title: LocalizedStringResource("keyParameter", defaultValue: "Key", table: "Widgets"))
  var key: String
  /// Creates an empty intent for App Intents decoding.
  init() {}
  /// Creates an intent for a keypad command.
  init(_ key: String) { self.key = key }
  /// Coordinates and persists the keypad mutation.
  func perform() async throws -> some IntentResult {
    try CurrencyStore.shared.press(key)
    WidgetCenter.shared.reloadAllTimelines()
    return .result()
  }
}
