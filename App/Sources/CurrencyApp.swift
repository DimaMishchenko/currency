import ConverterFeature
import CurrencySupport
import ExchangeRates
import LocalCurrencyOnboardingFeature
import RateDetailsFeature
import SwiftUI
import WidgetOnboardingFeature

@main
struct CurrencyApp: App {
  @State private var appearance = AppAppearance()
  private let history = HistoryService(directory: CurrencyStore.shared.directory)

  var body: some Scene {
    WindowGroup {
      ConverterScreen { code, reference, snapshot in
        RateDetailsScreen(code: code, reference: reference, snapshot: snapshot, history: history)
      } widgets: {
        WidgetOnboardingScreen { LocalCurrencyOnboardingScreen() }
      } localCurrency: {
        LocalCurrencyOnboardingScreen()
      } reconcileLocalCurrency: {
        LocalCurrencyAuthorization.reconcile()
      }
      .environment(appearance)
      .tint(appearance.accent)
    }
  }
}
