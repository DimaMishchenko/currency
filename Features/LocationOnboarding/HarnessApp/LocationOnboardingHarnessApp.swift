import DesignSystem
import Foundation
import LocalCurrency
import LocationOnboarding
import LocationOnboardingUI
import Observation
import SwiftUI

@MainActor @Observable private final class LocationHarnessState {
  var snapshot: LocationSnapshot
  init() {
    let args = ProcessInfo.processInfo.arguments
    if args.contains("ready") {
      snapshot = LocationSnapshot(
        phase: .ready, message: .saved,
        resolved: WidgetLocation(country: "CZ", currency: "CZK"),
        region: LocationMapRegion(
          latitude: 50.08, longitude: 14.43, latitudeDelta: 0.3, longitudeDelta: 0.3),
        permissionAuthorized: true)
    } else if args.contains("failure") {
      snapshot = LocationSnapshot(
        phase: .unavailable, message: .permissionDenied, permissionDenied: true)
    } else {
      snapshot = LocationSnapshot()
    }
  }
}

@main struct LocationOnboardingHarnessApp: App {
  @State private var flowID = UUID()
  @State private var state = LocationHarnessState()
  @State private var appearance = AppAppearance(
    theme: .system, accent: .primary, onThemeChange: { _ in }, onAccentChange: { _ in })
  var body: some Scene {
    WindowGroup {
      LocationOnboardingEntry(flowID: flowID)
        .environment(appearance)
        .tint(appearance.accent)
        .preferredColorScheme(appearance.theme.colorScheme)
        .environment(
          \.locationOnboardingDependencies,
          LocationOnboardingDependencies(
            readSnapshot: { state.snapshot }, reconcile: {},
            update: { _ in
              state.snapshot = LocationSnapshot(
                phase: .ready, message: .saved,
                resolved: WidgetLocation(country: "CZ", currency: "CZK"), permissionAuthorized: true
              )
            }, cancel: {},
            addResolvedCurrency: {}, now: { .now }, output: { _ in }))
    }
  }
}
