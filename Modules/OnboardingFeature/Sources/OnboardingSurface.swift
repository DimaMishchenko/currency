import SwiftUI

/// An adaptive raised surface that stays distinct from the page in both appearances.
struct OnboardingSurface: View {
  var radius: CGFloat = 24
  var selected = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    RoundedRectangle(cornerRadius: radius)
      .fill(Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground))
      .overlay {
        RoundedRectangle(cornerRadius: radius)
          .strokeBorder(
            .primary.opacity(selected ? 0.28 : colorScheme == .dark ? 0.12 : 0.07), lineWidth: 1)
      }
      .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 16, y: 6)
  }
}
