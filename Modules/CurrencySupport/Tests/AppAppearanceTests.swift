import Observation
import SwiftUI
import Testing
import os

@testable import CurrencySupport

@MainActor @Suite struct AppAppearanceTests {
  @Test func defaultsToAdaptivePrimaryAndCanResetCustomAccent() {
    let appearance = AppAppearance()
    #expect(appearance.accent == Color(uiColor: .label))
    appearance.accent = .purple
    #expect(appearance.accent == .purple)
    appearance.accent = Color(uiColor: .label)
    #expect(appearance.accent == Color(uiColor: .label))
  }

  @Test func changingAccentInvalidatesConsumers() {
    let appearance = AppAppearance()
    let changed = ChangeFlag()
    withObservationTracking {
      _ = appearance.accent
    } onChange: {
      changed.mark()
    }
    appearance.accent = .orange
    #expect(changed.value)
  }
}

private final class ChangeFlag: Sendable {
  private let storage = OSAllocatedUnfairLock(initialState: false)
  var value: Bool { storage.withLock { $0 } }
  func mark() { storage.withLock { $0 = true } }
}
