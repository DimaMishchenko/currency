import SwiftUI

/// Contrasting text or symbols placed directly inside a solid accent-colored button's label.
@available(iOS 26.0, *)
public struct AppAccentLabel: ViewModifier {
  @Environment(AppAppearance.self) private var appearance
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.isEnabled) private var isEnabled

  /// Creates the shared foreground treatment for primary-action labels.
  public init() {}

  /// Applies contrast to the label itself while keeping disabled text neutral.
  public func body(content: Content) -> some View {
    content.foregroundStyle(
      isEnabled
        ? appearance.accentForeground(colorScheme: colorScheme, contrast: contrast)
        : Color(uiColor: .secondaryLabel))
  }
}
