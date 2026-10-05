import DesignSystem
import ExchangeRates
import Observation
import Settings
import SettingsUI
import SwiftUI

@MainActor @Observable private final class SettingsHarnessState {
  var preferences = SettingsPreferences(theme: .system, accent: .primary)
  var failing: Bool
  let dated: Bool
  var rates: SettingsRateState {
    let date = Date(timeIntervalSince1970: 1_791_050_760)
    let snapshot = dated ? RateSnapshot(fetchedAt: date, checkedAt: date) : RateSnapshot()
    return SettingsRateState(snapshot: snapshot, codes: ["EUR", "USD"])
  }
  init(failing: Bool, dated: Bool) {
    self.failing = failing
    self.dated = dated
  }
}

@main struct SettingsHarnessApp: App {
  @State private var flowID = UUID()
  @State private var state: SettingsHarnessState
  @State private var appearance = AppAppearance(
    theme: .system, accent: .primary, onThemeChange: { _ in }, onAccentChange: { _ in })
  init() {
    _state = State(
      initialValue: SettingsHarnessState(
        failing: ProcessInfo.processInfo.arguments.contains("failure"),
        dated: ProcessInfo.processInfo.arguments.contains("dated")))
  }
  var body: some Scene {
    WindowGroup {
      NavigationStack { SettingsEntry(flowID: flowID) }
        .environment(
          \.locale,
          Locale(
            identifier: UserDefaults.standard.string(forKey: "AppleLocale")
              ?? Locale.current.identifier)
        )
        .environment(appearance)
        .tint(appearance.accent)
        .preferredColorScheme(appearance.theme.colorScheme)
        .environment(
          \.settingsDependencies,
          SettingsDependencies(
            readState: { state.rates },
            changes: { AsyncStream<Void>(bufferingPolicy: .unbounded) { _ in } },
            readPreferences: { state.preferences },
            setTheme: { state.preferences.theme = $0 },
            setAccent: { state.preferences.accent = $0 },
            setMetalUnit: { state.preferences.metalUnit = $0 },
            refresh: {
              if state.failing { throw CocoaError(.fileReadUnknown) }
              return state.rates
            }, replay: { if state.failing { throw CocoaError(.fileWriteUnknown) } },
            output: { _ in }))
    }
  }
}
