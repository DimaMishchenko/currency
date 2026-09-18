import CurrencySupport
import ExchangeRates
import SwiftUI

/// The widget presentations supplied by the app's composition root.
public enum OnboardingWidgetScene {
  case homeScreen, showcase
}

/// Owns first-launch setup and reveals the host's content after completion has been saved.
public struct OnboardingFlow<Widgets: View, Content: View>: View {
  @State private var model: OnboardingModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let widgets:
    (OnboardingWidgetScene, RateSnapshot, ConverterState, Binding<Bool>, @escaping () -> Void) ->
      Widgets
  private let content: (@escaping () throws -> Void) -> Content

  /// Creates setup with host-supplied widget scenes and the completed app destination.
  /// The content closure receives only a throwing operation for replaying setup.
  public init(
    store: CurrencyStore = .shared, service: RateService = RateService(),
    @ViewBuilder widgets:
      @escaping (
        OnboardingWidgetScene, RateSnapshot, ConverterState, Binding<Bool>, @escaping () -> Void
      ) -> Widgets,
    @ViewBuilder content: @escaping (@escaping () throws -> Void) -> Content
  ) {
    self.widgets = widgets
    self.content = content
    _model = State(initialValue: OnboardingModel(store: store, service: service))
  }

  /// Presents resumable setup or the completed app without exposing feature lifecycle state.
  public var body: some View {
    GeometryReader { geometry in
      ZStack {
        if model.isCompleted || model.step == .ready {
          content { try model.restart() }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(nil, value: model.isCompleted)
            .opacity(model.isCompleted ? 1 : 0)
            .allowsHitTesting(model.isCompleted)
            .accessibilityHidden(!model.isCompleted)
            .zIndex(0)
        }
        if !model.isCompleted {
          OnboardingScreen(model: model) { step, snapshot, input, guide, finished in
            widgets(step == .homeScreen ? .homeScreen : .showcase, snapshot, input, guide, finished)
          }
          .frame(width: geometry.size.width, height: geometry.size.height)
          .id(model.step == .ready)
          .transition(.opacity)
          .zIndex(1)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .background(Color(uiColor: .systemBackground))
    .animation(
      reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.54), value: model.step == .ready
    )
    .animation(
      reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.65), value: model.isCompleted)
  }
}
