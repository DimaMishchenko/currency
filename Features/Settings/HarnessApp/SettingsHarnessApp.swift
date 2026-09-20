import DesignSystem
import ExchangeRates
import Observation
import Settings
import SettingsUI
import SwiftUI

@MainActor @Observable private final class SettingsHarnessState {
  var preferences = SettingsPreferences(theme: .system, accent: .primary)
  var failing: Bool
  init(failing: Bool) { self.failing = failing }
}

@main struct SettingsHarnessApp: App {
  @State private var flowID = UUID()
  @State private var state: SettingsHarnessState
  @State private var appearance = AppAppearance(
    theme: .system, accent: .primary, onThemeChange: { _ in }, onAccentChange: { _ in })
  init() {
    _state = State(
      initialValue: SettingsHarnessState(
        failing: ProcessInfo.processInfo.arguments.contains("failure")))
  }
  var body: some Scene {
    WindowGroup {
      NavigationStack { SettingsEntry(flowID: flowID) }
        .environment(appearance)
        .tint(appearance.accent)
        .preferredColorScheme(appearance.theme.colorScheme)
        .environment(
          \.settingsDependencies,
          SettingsDependencies(
            readState: { SettingsRateState(snapshot: RateSnapshot(), codes: ["EUR", "USD"]) },
            changes: { AsyncStream<Void>(bufferingPolicy: .unbounded) { _ in } },
            readPreferences: { state.preferences },
            setTheme: { state.preferences.theme = $0 },
            setAccent: { state.preferences.accent = $0 },
            refresh: {
              if state.failing { throw CocoaError(.fileReadUnknown) }
              return SettingsRateState(snapshot: RateSnapshot(), codes: ["EUR", "USD"])
            }, replay: { if state.failing { throw CocoaError(.fileWriteUnknown) } },
            output: { _ in }))
    }
  }
}
