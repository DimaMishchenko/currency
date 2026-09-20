import Observation
import SwiftUI

/// Presentation values supplied by the host. Widgets retain their system appearance.
@MainActor @Observable
@available(iOS 26.0, *)
public final class AppAppearance {
  /// Preferred app color scheme; System follows the device.
  public enum Theme: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    /// Stable identity for preference lists.
    public var id: Self { self }
    /// A nil override restores the device color scheme.
    public var colorScheme: ColorScheme? {
      switch self {
      case .system: nil
      case .light: .light
      case .dark: .dark
      }
    }
  }

  /// Named adaptive system colors offered in Settings.
  public enum Accent: String, CaseIterable, Identifiable, Sendable {
    case primary, blue, indigo, purple, pink, red, orange, green, teal
    /// Stable identity for preference lists.
    public var id: Self { self }
    /// Resolves the selected adaptive system color.
    public var color: Color { Color(uiColor: uiColor) }

    var uiColor: UIColor {
      switch self {
      case .primary: .label
      case .blue: .systemBlue
      case .indigo: .systemIndigo
      case .purple: .systemPurple
      case .pink: .systemPink
      case .red: .systemRed
      case .orange: .systemOrange
      case .green: .systemGreen
      case .teal: .systemTeal
      }
    }

    var foregroundColor: UIColor {
      let background = uiColor
      return UIColor { traits in
        let resolved = background.resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: nil)
        func linear(_ value: CGFloat) -> CGFloat {
          value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return blackContrast >= whiteContrast ? .black : .white
      }
    }
  }

  private let onThemeChange: (Theme) -> Void
  private let onAccentChange: (Accent) -> Void
  /// Selected theme, saved whenever it changes.
  public var theme: Theme {
    didSet { onThemeChange(theme) }
  }
  /// Selected accent, saved whenever it changes.
  public var accentSelection: Accent {
    didSet { onAccentChange(accentSelection) }
  }
  /// Tint for actions, links, selections, and chart emphasis; not general content text.
  public var accent: Color { accentSelection.color }

  /// A contrasting label color for a solid accent fill in the current appearance.
  public func accentForeground(colorScheme: ColorScheme, contrast: ColorSchemeContrast) -> Color {
    let traits = UITraitCollection {
      $0.userInterfaceStyle = colorScheme == .dark ? .dark : .light
      $0.accessibilityContrast = contrast == .increased ? .high : .normal
    }
    return Color(uiColor: accentSelection.foregroundColor.resolvedColor(with: traits))
  }

  /// Creates presentation state with explicitly supplied host persistence.
  public init(
    theme: Theme, accent: Accent, onThemeChange: @escaping (Theme) -> Void,
    onAccentChange: @escaping (Accent) -> Void
  ) {
    self.theme = theme
    self.accentSelection = accent
    self.onThemeChange = onThemeChange
    self.onAccentChange = onAccentChange
  }
}

/// Shared styles for custom content. Native controls keep their platform defaults.
@available(iOS 26.0, *)
public enum AppStyle {
  /// Shared spacing scale in points.
  public enum Space {
    /// A 2-point gap.
    public static let xxs: CGFloat = 2
    /// A 4-point gap.
    public static let xs: CGFloat = 4
    /// A 8-point gap.
    public static let small: CGFloat = 8
    /// A 12-point gap.
    public static let medium: CGFloat = 12
    /// A 16-point gap.
    public static let large: CGFloat = 16
    /// A 32-point gap.
    public static let section: CGFloat = 32
    /// A 48-point gap.
    public static let spacious: CGFloat = 48
  }

  /// Adaptive widget fills, borders, and corner radii.
  public enum Widget {
    /// Corner radius for compact keys and tiles.
    public static let keyRadius: CGFloat = 10
    /// Corner radius for standard currency tiles.
    public static let tileRadius: CGFloat = 14
    /// Primary-color opacity behind a key.
    public static let keyFill: Double = 0.09
    /// Primary-color opacity behind an unselected tile.
    public static let tileFill: Double = 0.045
    /// Primary-color opacity behind the active currency.
    public static let selectedFill: Double = 0.13
    /// Primary-color opacity for key outlines.
    public static let keyBorder: Double = 0.035
    /// Primary-color opacity for the active tile outline.
    public static let selectedBorder: Double = 0.45
  }

  /// Semantic system fonts retain Dynamic Type and accessibility weight adjustments.
  public static func font(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
    .system(style, design: .rounded, weight: weight)
  }
}
