import ConverterFeature
import CurrencySupport
import ExchangeRates
import LocalCurrencyOnboardingFeature
import OnboardingFeature
import RateDetailsFeature
import SwiftUI
import WidgetOnboardingFeature

@main
struct CurrencyApp: App {
  @State private var appearance = AppAppearance()
  @State private var showsLocalCurrency = false
  @State private var inputRevision = 0
  private let store: CurrencyStore

  init() {
    store = .shared
    history = HistoryService(directory: store.directory)
  }
  private let history: HistoryService

  var body: some Scene {
    WindowGroup {
      OnboardingFlow(store: store) { scene, snapshot, input, guide, finished in
        if scene == .homeScreen {
          OnboardingHomeScreen(snapshot: snapshot, input: input)
        } else {
          OnboardingWidgetShowcase(
            snapshot: snapshot, input: input, guideRequested: guide, onGuideFinished: finished)
        }
      } content: { replayOnboarding in
        converter(replayOnboarding: replayOnboarding)
      }
      .onOpenURL { url in
        if url.scheme == "currency", url.host == "local-currency" {
          showsLocalCurrency = true
        }
      }
      .sheet(isPresented: $showsLocalCurrency, onDismiss: { inputRevision += 1 }) {
        LocalCurrencyOnboardingScreen()
      }
      .environment(appearance)
      .tint(appearance.accent)
    }
  }

  private func converter(replayOnboarding: @escaping () throws -> Void) -> some View {
    ConverterScreen(store: store, inputRevision: inputRevision) { code, reference, snapshot in
      RateDetailsScreen(code: code, reference: reference, snapshot: snapshot, history: history)
    } widgets: {
      WidgetOnboardingScreen { LocalCurrencyOnboardingScreen() }
    } reconcileLocalCurrency: {
      LocalCurrencyAuthorization.reconcile()
    } replayOnboarding: {
      try replayOnboarding()
    }
  }
}
