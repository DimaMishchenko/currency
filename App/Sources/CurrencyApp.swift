import ConverterFeature
import CurrencySupport
import ExchangeRates
import RateDetailsFeature
import SwiftUI

@main
struct CurrencyApp: App {
  @State private var appearance = AppAppearance()
  private let history = HistoryService(directory: CurrencyStore.shared.directory)

  var body: some Scene {
    WindowGroup {
      ConverterScreen { code, reference, snapshot in
        RateDetailsScreen(code: code, reference: reference, snapshot: snapshot, history: history)
      }
      .environment(appearance)
      .tint(appearance.accent)
    }
  }
}
