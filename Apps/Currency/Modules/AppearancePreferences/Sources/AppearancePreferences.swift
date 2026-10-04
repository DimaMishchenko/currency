import Foundation
import Observation

/// Authoritative persisted appearance choices; presentation maps these values to system colors.
@MainActor @Observable
public final class AppearancePreferences {
  /// Persisted appearance override; system follows the host device.
  public enum Theme: String, CaseIterable, Sendable { case system, light, dark }
  /// Named system accent choices with stable persisted raw values.
  public enum Accent: String, CaseIterable, Sendable {
    case primary, blue, indigo, purple, pink, red, orange, green, teal
  }
  private let defaults: UserDefaults
  /// The selected theme, persisted under the existing preference key.
  public var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "appearance.theme") } }
  /// The selected accent, persisted under the existing preference key.
  public var accent: Accent {
    didSet { defaults.set(accent.rawValue, forKey: "appearance.accent") }
  }
  /// Restores choices from explicit preferences, tolerating missing or future values.
  public init(defaults: UserDefaults) {
    self.defaults = defaults
    theme = Theme(rawValue: defaults.string(forKey: "appearance.theme") ?? "") ?? .system
    accent = Accent(rawValue: defaults.string(forKey: "appearance.accent") ?? "") ?? .primary
  }
}
