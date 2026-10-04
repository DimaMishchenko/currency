import SwiftUI
import TipKit

@main
struct CurrencyApp: App {
  private let composition = AppComposition()
  init() {
    try? Tips.configure()
  }
  var body: some Scene {
    WindowGroup { CurrencyRoot(composition: composition) }
  }
}
