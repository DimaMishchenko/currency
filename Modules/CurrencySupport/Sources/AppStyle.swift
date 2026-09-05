import Observation
import SwiftUI

/// App-owned appearance state. A future settings screen can bind to `accent`.
/// The default follows the system's primary label color in light, dark, and increased contrast modes.
@MainActor @Observable
public final class AppAppearance {
  public var accent: Color

  public init(accent: Color = Color(uiColor: .label)) {
    self.accent = accent
  }
}

/// Shared styles for custom content. Native controls keep their platform defaults.
public enum AppStyle {
  public enum Space {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let section: CGFloat = 32
    public static let spacious: CGFloat = 48
  }

  /// Semantic system fonts retain Dynamic Type and accessibility weight adjustments.
  public static func font(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
    .system(style, design: .rounded, weight: weight)
  }
}
