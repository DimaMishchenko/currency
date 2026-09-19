import ConverterFeature
import CurrencySupport
import ExchangeRates
import LocalCurrencyOnboardingFeature
import OnboardingFeature
import RateDetailsFeature
import SettingsFeature
import SwiftUI
import UIKit
import WidgetOnboardingFeature

@main
struct CurrencyApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appearance = AppAppearance()
  @State private var showsLocalCurrency = false
  @State private var addsLocalCurrencyToApp = false
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
          addsLocalCurrencyToApp = false
          showsLocalCurrency = true
        }
      }
      .sheet(isPresented: $showsLocalCurrency, onDismiss: { inputRevision += 1 }) {
        LocalCurrencyOnboardingScreen(
          addsResolvedCurrencyToApp: addsLocalCurrencyToApp && !store.input().usesLocalCurrency)
      }
      .onChange(of: scenePhase, initial: true) { _, phase in
        AppHaptics.configure(active: phase == .active, reducedMotion: reduceMotion)
      }
      .onChange(of: reduceMotion) { _, value in
        AppHaptics.configure(active: scenePhase == .active, reducedMotion: value)
      }
      .task(id: scenePhase) {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
          await LocalCurrencyController.foreground.refreshIfNeeded()
          inputRevision += 1
          do { try await Task.sleep(for: .seconds(300)) } catch { break }
        }
      }
      .environment(appearance)
      .tint(appearance.accent)
      .preferredColorScheme(appearance.theme.colorScheme)
    }
  }

  private func converter(replayOnboarding: @escaping () throws -> Void) -> some View {
    ConverterScreen(store: store, inputRevision: inputRevision) { code, reference, snapshot in
      RateDetailsScreen(code: code, reference: reference, snapshot: snapshot, history: history)
    } widgets: {
      WidgetOnboardingScreen { LocalCurrencyOnboardingScreen() }
    } reconcileLocalCurrency: {
      LocalCurrencyAuthorization.reconcile()
    } configureLocalCurrency: {
      addsLocalCurrencyToApp = true
      showsLocalCurrency = true
    } settings: { snapshot, codes, isRefreshing, warning, refresh in
      SettingsScreen(
        snapshot: snapshot, codes: codes, isRefreshing: isRefreshing, warning: warning,
        refresh: refresh, manageLocation: manageLocationPermission,
        replayOnboarding: replayOnboarding)
    }
  }

  private func manageLocationPermission() {
    LocalCurrencyAuthorization.managePermission {
      addsLocalCurrencyToApp = false
      showsLocalCurrency = true
    } openSettings: {
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
      UIApplication.shared.open(url)
    }
  }
}
