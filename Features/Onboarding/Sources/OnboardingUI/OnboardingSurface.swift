import Onboarding
import SwiftUI

/// Choices blend into the page; standalone cards can opt into elevation.
struct OnboardingSurface: View {
  var radius: CGFloat = 24
  var selected = false
  var raised = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    RoundedRectangle(cornerRadius: radius)
      .fill(
        Color(
          uiColor: raised && colorScheme == .dark ? .secondarySystemBackground : .systemBackground)
      )
      .overlay {
        RoundedRectangle(cornerRadius: radius)
          .strokeBorder(
            selected
              ? AnyShapeStyle(.tint)
              : AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)),
            lineWidth: selected ? 1.5 : 1)
      }
      .shadow(color: .black.opacity(raised && colorScheme == .light ? 0.06 : 0), radius: 16, y: 6)
  }
}
