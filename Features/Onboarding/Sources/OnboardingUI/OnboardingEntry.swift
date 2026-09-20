import Conversion
import ExchangeRates
import Foundation
import Onboarding
import SwiftUI

/// Widget presentations supplied explicitly by the executable's composition.
public enum OnboardingWidgetScene {
  case homeScreen, showcase
}

private struct OnboardingDependenciesKey: EnvironmentKey {
  static let defaultValue: OnboardingDependencies? = nil
}

extension EnvironmentValues {
  /// Required setup capabilities, captured once by each flow identity.
  public var onboardingDependencies: OnboardingDependencies? {
    get { self[OnboardingDependenciesKey.self] }
    set { self[OnboardingDependenciesKey.self] = newValue }
  }
}

/// The production setup entry. The application owns completion routing and replay identity.
public struct OnboardingEntry<Widgets: View>: View {
  @Environment(\.onboardingDependencies) private var dependencies
  private let flowID: UUID
  private let onOutput: (OnboardingOutput) -> Void
  private let widgets:
    (OnboardingWidgetScene, RateSnapshot, ConverterState, Binding<Bool>, @escaping () -> Void) ->
      Widgets

  /// Creates a flow with explicit widget presentation and semantic outcome handling.
  public init(
    flowID: UUID,
    onOutput: @escaping (OnboardingOutput) -> Void,
    @ViewBuilder widgets:
      @escaping (
        OnboardingWidgetScene, RateSnapshot, ConverterState, Binding<Bool>, @escaping () -> Void
      ) -> Widgets
  ) {
    self.flowID = flowID
    self.onOutput = onOutput
    self.widgets = widgets
  }

  /// Resolves required dependencies only at the UI boundary.
  public var body: some View {
    if let dependencies {
      OnboardingFlowContent(dependencies: dependencies, onOutput: onOutput, widgets: widgets)
        .id(flowID)
    } else {
      missingDependencies()
    }
  }

  private func missingDependencies() -> Never {
    preconditionFailure("OnboardingEntry requires onboardingDependencies in its environment")
  }
}

private struct OnboardingFlowContent<Widgets: View>: View {
  @State private var model: OnboardingModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let onOutput: (OnboardingOutput) -> Void
  let widgets:
    (OnboardingWidgetScene, RateSnapshot, ConverterState, Binding<Bool>, @escaping () -> Void) ->
      Widgets

  init(
    dependencies: OnboardingDependencies,
    onOutput: @escaping (OnboardingOutput) -> Void,
    @ViewBuilder widgets:
      @escaping (
        OnboardingWidgetScene, RateSnapshot, ConverterState, Binding<Bool>, @escaping () -> Void
      ) -> Widgets
  ) {
    _model = State(initialValue: OnboardingModel(dependencies: dependencies))
    self.onOutput = onOutput
    self.widgets = widgets
  }

  var body: some View {
    ZStack {
      OnboardingScreen(model: model) { step, snapshot, input, guide, finished in
        widgets(step == .homeScreen ? .homeScreen : .showcase, snapshot, input, guide, finished)
      }
      .id(model.step == .ready)
      .transition(.opacity)
    }
    .background(Color(uiColor: .systemBackground))
    .animation(
      reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.54), value: model.step == .ready
    )
    .onChange(of: model.step, initial: true) { _, step in
      if step == .ready { onOutput(.finalePresented) }
    }
    .onChange(of: model.isCompleted, initial: true) { _, completed in
      if completed { onOutput(.completed) }
    }
    .task { await model.run() }
  }
}
