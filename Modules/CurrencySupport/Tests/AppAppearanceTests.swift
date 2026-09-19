import Observation
import SwiftUI
import Testing
import os

@testable import CurrencySupport

@MainActor @Suite struct AppAppearanceTests {
  private func isolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "AppAppearanceTests.\(UUID().uuidString)")!
  }

  @Test func defaultsToSystemAppearance() {
    let appearance = AppAppearance(defaults: isolatedDefaults())
    #expect(appearance.theme == .system)
    #expect(appearance.theme.colorScheme == nil)
    #expect(appearance.accent == Color(uiColor: .label))
  }

  @Test func selectionsSurviveRecreationAndReset() {
    let defaults = isolatedDefaults()
    let appearance = AppAppearance(defaults: defaults)
    appearance.theme = .dark
    appearance.accentSelection = .purple
    let restored = AppAppearance(defaults: defaults)
    #expect(restored.theme.colorScheme == .dark)
    #expect(restored.accent == Color(uiColor: .systemPurple))
    restored.theme = .light
    #expect(restored.theme.colorScheme == .light)
    restored.theme = .system
    restored.accentSelection = .primary
    let reset = AppAppearance(defaults: defaults)
    #expect(reset.theme.colorScheme == nil)
    #expect(reset.accent == Color(uiColor: .label))
  }

  @Test func unknownSavedValuesFallBackToDefaults() {
    let defaults = isolatedDefaults()
    defaults.set("unknown", forKey: "appearance.theme")
    defaults.set("unknown", forKey: "appearance.accent")
    let appearance = AppAppearance(defaults: defaults)
    #expect(appearance.theme == .system)
    #expect(appearance.accentSelection == .primary)
  }

  @Test func prominentLabelsHaveReadableContrastForEveryAccentAndAppearance() throws {
    let appearance = AppAppearance(defaults: isolatedDefaults())
    for accent in AppAppearance.Accent.allCases {
      appearance.accentSelection = accent
      for style in [UIUserInterfaceStyle.light, .dark] {
        for contrast in [UIAccessibilityContrast.normal, .high] {
          let traits = UITraitCollection {
            $0.userInterfaceStyle = style
            $0.accessibilityContrast = contrast
          }
          let fill = try luminance(accent.uiColor, traits: traits)
          let label = try luminance(
            UIColor(
              appearance.accentForeground(
                colorScheme: style == .dark ? .dark : .light,
                contrast: contrast == .high ? .increased : .standard)), traits: traits)
          let ratio = (max(fill, label) + 0.05) / (min(fill, label) + 0.05)
          #expect(ratio >= 4.5, "Accent \(accent), style \(style), contrast \(contrast): \(ratio)")
        }
      }
    }
  }

  @Test func brightAndDarkFillsChooseOppositeLabelColors() {
    let light = UITraitCollection(userInterfaceStyle: .light)
    let dark = UITraitCollection(userInterfaceStyle: .dark)
    #expect(AppAppearance.Accent.orange.foregroundColor.resolvedColor(with: light) == .black)
    #expect(AppAppearance.Accent.primary.foregroundColor.resolvedColor(with: light) == .white)
    #expect(AppAppearance.Accent.primary.foregroundColor.resolvedColor(with: dark) == .black)
  }

  private func luminance(_ color: UIColor, traits: UITraitCollection) throws -> Double {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let converted = try #require(
      color.resolvedColor(with: traits).cgColor
        .converted(
          to: space, intent: .relativeColorimetric, options: nil))
    let components = try #require(converted.components)
    let linear = components.prefix(3)
      .map { component in
        let value = Double(component)
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
      }
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
  }

  @Test func changingAccentInvalidatesConsumers() {
    let appearance = AppAppearance(defaults: isolatedDefaults())
    let changed = ChangeFlag()
    withObservationTracking {
      _ = appearance.accent
    } onChange: {
      changed.mark()
    }
    appearance.accentSelection = .orange
    #expect(changed.value)
  }
}

private final class ChangeFlag: Sendable {
  private let storage = OSAllocatedUnfairLock(initialState: false)
  var value: Bool { storage.withLock { $0 } }
  func mark() { storage.withLock { $0 = true } }
}
