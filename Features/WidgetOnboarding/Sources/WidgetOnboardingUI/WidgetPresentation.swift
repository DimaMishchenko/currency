import SwiftUI

/// App-owned presentation around a widget surface that can request another feature.
/// Each invocation must retain its own presenter identity for the lifetime of that surface.
@MainActor
public struct WidgetOnboardingPresentation {
  let decorate: (AnyView) -> AnyView

  /// Supplies a presenter without making widget UI depend on the destination feature.
  public init(decorate: @escaping (AnyView) -> AnyView) {
    self.decorate = decorate
  }
}

private struct WidgetOnboardingPresentationKey: EnvironmentKey {
  static let defaultValue: WidgetOnboardingPresentation? = nil
}

extension EnvironmentValues {
  /// Required app presentation wiring for widget tutorials and collection surfaces.
  public var widgetOnboardingPresentation: WidgetOnboardingPresentation? {
    get { self[WidgetOnboardingPresentationKey.self] }
    set { self[WidgetOnboardingPresentationKey.self] = newValue }
  }
}

/// Resolves the decorator outside content so its environment reaches the requesting view.
struct WidgetPresentation<Content: View>: View {
  @Environment(\.widgetOnboardingPresentation) private var presentation
  private let content: Content

  init(@ViewBuilder content: () -> Content) { self.content = content() }

  var body: some View {
    if let presentation {
      presentation.decorate(AnyView(content))
    } else {
      missingPresentation()
    }
  }

  private func missingPresentation() -> Never {
    preconditionFailure("Widget tutorial and collection require widgetOnboardingPresentation")
  }
}
