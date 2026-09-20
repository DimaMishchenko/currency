import DesignSystem
import Settings
import SwiftUI

private struct SettingsDependenciesKey: EnvironmentKey {
  static let defaultValue: SettingsDependencies? = nil
}
public extension EnvironmentValues {
  var settingsDependencies: SettingsDependencies? {
    get { self[SettingsDependenciesKey.self] }
    set { self[SettingsDependenciesKey.self] = newValue }
  }
}

/// A production entry retaining its model across feature-local navigation.
public struct SettingsEntry: View {
  @Environment(\.settingsDependencies) private var dependencies
  private let flowID: UUID
  /// Creates a Settings presentation with an explicit flow identity.
  public init(flowID: UUID) { self.flowID = flowID }
  /// Renders the production flow using its explicitly supplied dependencies.
  public var body: some View {
    if let dependencies {
      SettingsFlow(dependencies: dependencies).id(flowID)
    } else {
      missingDependencies()
    }
  }
  private func missingDependencies() -> Never {
    preconditionFailure("SettingsEntry requires settingsDependencies from composition")
  }
}

private struct SettingsFlow: View {
  @State private var lifetime: SettingsFlowLifetime
  init(dependencies: SettingsDependencies) {
    _lifetime = State(initialValue: SettingsFlowLifetime(dependencies: dependencies))
  }
  var body: some View {
    SettingsScreen(model: lifetime.model)
      .onAppear { lifetime.start() }
  }
}
