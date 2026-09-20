import LocationOnboarding
import SwiftUI

private struct LocationOnboardingDependenciesKey: EnvironmentKey {
  static let defaultValue: LocationOnboardingDependencies? = nil
}
public extension EnvironmentValues {
  var locationOnboardingDependencies: LocationOnboardingDependencies? {
    get { self[LocationOnboardingDependenciesKey.self] }
    set { self[LocationOnboardingDependenciesKey.self] = newValue }
  }
}

/// Presents the production flow with host-owned permission and persistence operations.
public struct LocationOnboardingEntry: View {
  @Environment(\.locationOnboardingDependencies) private var dependencies
  private let flowID: UUID
  private let addsResolvedCurrencyToApp: Bool
  /// Creates a location flow with an identity and confirmation policy.
  public init(flowID: UUID, addsResolvedCurrencyToApp: Bool = false) {
    self.flowID = flowID
    self.addsResolvedCurrencyToApp = addsResolvedCurrencyToApp
  }
  /// Renders the production flow using its explicitly supplied dependencies.
  public var body: some View {
    if let dependencies {
      LocationOnboardingFlow(
        dependencies: dependencies, addsResolvedCurrencyToApp: addsResolvedCurrencyToApp
      )
      .id(flowID)
    } else {
      missingDependencies()
    }
  }
  private func missingDependencies() -> Never {
    preconditionFailure(
      "LocationOnboardingEntry requires locationOnboardingDependencies from composition")
  }
}

private struct LocationOnboardingFlow: View {
  @State private var model: LocationOnboardingModel
  init(dependencies: LocationOnboardingDependencies, addsResolvedCurrencyToApp: Bool) {
    _model = State(
      initialValue: LocationOnboardingModel(
        dependencies: dependencies, addsResolvedCurrencyToApp: addsResolvedCurrencyToApp))
  }
  var body: some View {
    LocalCurrencyOnboardingScreen(model: model).task { await model.run() }
  }
}
