import AppIntents
import Foundation

struct OpenWatchCurrencyIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Currency"
  static var isDiscoverable: Bool { false }
  static var supportedModes: IntentModes { .foreground }

  func perform() async throws -> some IntentResult { .result() }
}
