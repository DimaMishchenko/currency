import Foundation
import Observation
import Synchronization
import Testing

@testable import AppearancePreferences

@MainActor @Suite struct AppearancePreferencesTests {
  private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let name = "Currency.AppearancePreferencesTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
  }

  @Test func missingAndUnknownValuesUseDefaultsWithoutRewritingStorage() throws {
    try withDefaults { defaults in
      let initial = AppearancePreferences(defaults: defaults)
      #expect(initial.theme == .system)
      #expect(initial.accent == .primary)
      #expect(defaults.object(forKey: "appearance.theme") == nil)
      defaults.set("future-theme", forKey: "appearance.theme")
      defaults.set("future-accent", forKey: "appearance.accent")
      let unknown = AppearancePreferences(defaults: defaults)
      #expect(unknown.theme == .system)
      #expect(unknown.accent == .primary)
      #expect(defaults.string(forKey: "appearance.theme") == "future-theme")
      #expect(defaults.string(forKey: "appearance.accent") == "future-accent")
    }
  }

  @Test func oldKeysAndAllValuesSurviveRecreation() throws {
    try withDefaults { defaults in
      defaults.set("dark", forKey: "appearance.theme")
      defaults.set("purple", forKey: "appearance.accent")
      let preferences = AppearancePreferences(defaults: defaults)
      #expect(preferences.theme == .dark)
      #expect(preferences.accent == .purple)
      for theme in AppearancePreferences.Theme.allCases {
        preferences.theme = theme
        #expect(AppearancePreferences(defaults: defaults).theme == theme)
        #expect(defaults.string(forKey: "appearance.theme") == theme.rawValue)
      }
      for accent in AppearancePreferences.Accent.allCases {
        preferences.accent = accent
        #expect(AppearancePreferences(defaults: defaults).accent == accent)
        #expect(defaults.string(forKey: "appearance.accent") == accent.rawValue)
      }
    }
  }

  @Test func changingPreferenceInvalidatesObservedConsumers() throws {
    try withDefaults { defaults in
      let preferences = AppearancePreferences(defaults: defaults)
      let changed = Mutex(false)
      withObservationTracking {
        _ = preferences.accent
      } onChange: {
        changed.withLock { $0 = true }
      }
      preferences.accent = .orange
      #expect(changed.withLock { $0 })
      #expect(defaults.string(forKey: "appearance.accent") == "orange")
    }
  }
}
