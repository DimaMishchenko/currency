import Conversion
import DesignSystem
import ExchangeRates
import Onboarding
import OnboardingUI
import SwiftUI
import WidgetOnboarding
import WidgetOnboardingUI

@MainActor
private final class OnboardingHarnessFixture {
  let name: String
  var progress: OnboardingProgress?
  var input = ConverterState()
  var rates: RateSnapshot
  var failedSave = false

  init(name: String) {
    self.name = name
    let now = Date.now
    rates = RateSnapshot(
      quotes: [
        "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .ecb)),
        "USD": ExchangeRate(1.08, published: "2026-09-19", source: .init(provider: .ecb)),
        "GBP": ExchangeRate(0.84, published: "2026-09-19", source: .init(provider: .ecb))
      ], fetchedAt: now)
    if ["loading", "offline", "interrupted"].contains(name) { rates = RateSnapshot() }
    var draft = input
    draft.setAmount("100")
    if name == "selection" || name == "save-failure" {
      progress = OnboardingProgress(draft: draft, step: .selection)
    }
    if name == "finale" { progress = OnboardingProgress(draft: draft, step: .ready) }
  }

  var dependencies: OnboardingDependencies {
    OnboardingDependencies(
      loadProgress: { self.progress },
      saveProgress: {
        if self.name == "save-failure", !self.failedSave {
          self.failedSave = true
          throw CocoaError(.fileWriteOutOfSpace)
        }
        self.progress = $0
      },
      readInput: { self.input },
      editInput: { $0(&self.input) },
      readRates: { self.rates },
      saveRates: { rates, _ in
        self.rates = rates; return rates
      },
      bootstrap: { previous, _ in
        let name = self.name
        return AsyncStream { continuation in
          let task = Task {
            if name == "loading" || name == "interrupted" {
              do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
            continuation.yield(
              BootstrapUpdate(
                snapshot: previous, isFinal: true, failure: name == "offline" ? .offline : nil))
            continuation.finish()
          }
          continuation.onTermination = { _ in task.cancel() }
        }
      }, now: { .now })
  }
}

@main
struct OnboardingHarnessApp: App {
  @State private var flowID = UUID()
  @State private var fixture: OnboardingHarnessFixture
  @State private var appearance = AppAppearance(
    theme: .system, accent: .primary, onThemeChange: { _ in }, onAccentChange: { _ in })

  init() {
    let arguments = ProcessInfo.processInfo.arguments
    let index = arguments.firstIndex(of: "--case")
    let name =
      index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "normal"
    _fixture = State(initialValue: OnboardingHarnessFixture(name: name))
  }

  var body: some Scene {
    WindowGroup {
      OnboardingEntry(flowID: flowID, onOutput: { _ in }) {
        scene, snapshot, input, guide, finished in
        if scene == .homeScreen {
          OnboardingHomeScreen(snapshot: snapshot, input: input)
        } else {
          OnboardingWidgetShowcase(
            snapshot: snapshot, input: input, guideRequested: guide, onGuideFinished: finished)
        }
      }
      .environment(\.widgetOnboardingDependencies, WidgetOnboardingDependencies(output: { _ in }))
      .environment(\.onboardingDependencies, fixture.dependencies)
      .environment(
        \.widgetOnboardingPresentation,
        WidgetOnboardingPresentation { AnyView(HarnessWidgetPresentation(content: $0)) }
      )
      .environment(appearance)
      .tint(appearance.accent)
      .preferredColorScheme(appearance.theme.colorScheme)
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
