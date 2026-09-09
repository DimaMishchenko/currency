import Observation
import SwiftUI

/// App-owned appearance state. A future settings screen can bind to `accent`.
/// The default follows the system's primary label color in light, dark, and increased contrast modes.
@MainActor @Observable
public final class AppAppearance {
  /// Accent shared by custom app content and controls.
  public var accent: Color

  /// Creates appearance state with an adaptive system-label accent by default.
  public init(accent: Color = Color(uiColor: .label)) {
    self.accent = accent
  }
}

/// Shared styles for custom content. Native controls keep their platform defaults.
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
