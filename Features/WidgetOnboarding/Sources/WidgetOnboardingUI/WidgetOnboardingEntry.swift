import SwiftUI
import WidgetOnboarding

private struct WidgetOnboardingDependenciesKey: EnvironmentKey {
  static let defaultValue: WidgetOnboardingDependencies? = nil
}
public extension EnvironmentValues {
  var widgetOnboardingDependencies: WidgetOnboardingDependencies? {
    get { self[WidgetOnboardingDependenciesKey.self] }
    set { self[WidgetOnboardingDependenciesKey.self] = newValue }
  }
}

/// Widget discovery and isolated tutorials, with one identity per presentation flow.
public struct WidgetOnboardingEntry: View {
  @Environment(\.widgetOnboardingDependencies) private var dependencies
  private let flowID: UUID
  /// Creates a widget discovery flow with its own presentation identity.
  public init(flowID: UUID) { self.flowID = flowID }
  /// Renders the production flow using its explicitly supplied dependencies.
  public var body: some View {
    if let dependencies {
      WidgetGuide(output: dependencies.output).id(flowID)
    } else {
      missingDependencies()
    }
  }
  private func missingDependencies() -> Never {
    preconditionFailure(
      "WidgetOnboardingEntry requires widgetOnboardingDependencies from composition")
  }
}
