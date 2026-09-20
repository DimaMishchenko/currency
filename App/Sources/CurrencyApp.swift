import SwiftUI

@main
struct CurrencyApp: App {
  private let composition = AppComposition()
  var body: some Scene {
    WindowGroup { CurrencyRoot(composition: composition) }
  }
}
