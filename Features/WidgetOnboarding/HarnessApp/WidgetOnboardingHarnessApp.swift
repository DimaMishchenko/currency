import Conversion
import DesignSystem
import SwiftUI
import WidgetOnboarding
import WidgetOnboardingUI

@main struct WidgetOnboardingHarnessApp: App {
  @State private var flowID = UUID()
  @State private var guideRequested = false
  @State private var appearance = AppAppearance(
    theme: .system, accent: .primary, onThemeChange: { _ in }, onAccentChange: { _ in })
  var body: some Scene {
    WindowGroup {
      Group {
        if ProcessInfo.processInfo.arguments.contains("home") {
          OnboardingHomeScreen(snapshot: WidgetPreviewState.rates, input: ConverterState())
        } else if ProcessInfo.processInfo.arguments.contains("showcase") {
          NavigationStack {
            OnboardingWidgetShowcase(
              snapshot: WidgetPreviewState.rates, input: ConverterState(),
              guideRequested: $guideRequested, onGuideFinished: {})
          }
        } else {
          WidgetOnboardingEntry(flowID: flowID)
        }
      }
      .environment(
        \.widgetOnboardingPresentation,
        WidgetOnboardingPresentation { AnyView(HarnessWidgetPresentation(content: $0)) }
      )
      .environment(appearance)
      .tint(appearance.accent)
      .preferredColorScheme(appearance.theme.colorScheme)
      .environment(\.widgetOnboardingDependencies, WidgetOnboardingDependencies(output: { _ in }))
    }
  }
}

/// Acknowledges cross-feature output without requesting real location permission in the harness.
private struct HarnessWidgetPresentation: View {
  let content: AnyView
  @State private var locationRequested = false

  var body: some View {
    content
      .environment(
        \.widgetOnboardingDependencies,
        WidgetOnboardingDependencies { output in
          if case .locationRequested = output { locationRequested = true }
        }
      )
      .alert("Location requested", isPresented: $locationRequested) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(
          "The application presents location setup here. This harness keeps permission unchanged.")
      }
  }
}
