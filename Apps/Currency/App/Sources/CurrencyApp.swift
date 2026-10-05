import SwiftUI
import TipKit

@main
struct CurrencyApp: App {
  private let composition = AppComposition.launch()
  init() {
    try? Tips.configure()
    composition.startCompanionSync()
  }
  var body: some Scene {
    WindowGroup { CurrencyRoot(composition: composition) }
  }
}
