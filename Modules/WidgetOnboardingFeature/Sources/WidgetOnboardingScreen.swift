import SwiftUI

/// Widget discovery, isolated interactive previews, and native add/edit tutorials.
public struct WidgetOnboardingScreen: View {
  private let localCurrency: @MainActor () -> AnyView

  /// Creates onboarding with a local-currency destination supplied by the app.
  public init<Destination: View>(@ViewBuilder localCurrency: @escaping @MainActor () -> Destination)
  {
    self.localCurrency = { AnyView(localCurrency()) }
  }

  /// The widget showcase and its child guides.
  public var body: some View {
    WidgetGuide().environment(\.localCurrencyDestination, localCurrency)
  }
}

private struct LocalCurrencyDestinationKey: EnvironmentKey {
  static let defaultValue: @MainActor () -> AnyView = { AnyView(EmptyView()) }
}

extension EnvironmentValues {
  var localCurrencyDestination: @MainActor () -> AnyView {
    get { self[LocalCurrencyDestinationKey.self] }
    set { self[LocalCurrencyDestinationKey.self] = newValue }
  }
}
