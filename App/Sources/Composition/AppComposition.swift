import AppearancePreferences
import Conversion
import CoreLocation
import CurrencyApplication
import CurrencyDetails
import ExchangeRates
import ForegroundRefresh
import Foundation
import Home
import LocalCurrency
import LocationOnboarding
import Observation
import Onboarding
import Settings
import UIKit
import WidgetKit

/// Live capabilities are assembled once for this executable; scenes retain their own flow state.
@MainActor
final class AppComposition {
  let rates: RateStore
  let conversion: ConversionStore
  let local: LocalCurrencyStore
  let progress: OnboardingProgressStore
  let history: HistoryService
  let service = RateService()
  let appearance = AppearancePreferences(defaults: .standard)
  private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]
  private(set) var warning: RefreshWarning?
  private var rateIssue: HomeIssue?
  private var widgetReload: Task<Void, Never>?
  lazy var foregroundLocation = makeLocationController()
  lazy var foreground = ForegroundRefresh(
    dependencies: .init(
      refreshRates: { [weak self] in _ = try? await self?.refresh(force: false) },
      refreshLocalCurrency: { [weak self] in await self?.foregroundLocation.refreshIfNeeded() },
      changed: { [weak self] in self?.changed() }))

  init(directory: URL = AppGroup.directory) {
    rates = RateStore(directory: directory)
    conversion = ConversionStore(directory: directory)
    local = LocalCurrencyStore(directory: directory)
    progress = OnboardingProgressStore(directory: directory)
    history = HistoryService(directory: directory)
  }
  func makeScene() -> CurrencyScene {
    CurrencyScene(
      completed: progress.load().map { $0.version == 1 && $0.completed } == true,
      replay: { [self] in
        try progress.restart(input: conversion.input())
      })
  }
  func changed() { for observer in observers.values { observer.yield(()) } }
  func changes() -> AsyncStream<Void> {
    let id = UUID()
    return AsyncStream { continuation in
      observers[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor in self?.observers.removeValue(forKey: id) }
      }
    }
  }
  func edit(_ mutation: (inout ConverterState) throws -> Void) throws -> ConverterState {
    let input = try conversion.updateInput(mutation)
    changed()
    widgetReload?.cancel()
    widgetReload = Task {
      do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
      WidgetCenter.shared.reloadAllTimelines()
    }
    return input
  }
  func refresh(force: Bool) async throws -> RefreshResult {
    do {
      let result = try await rates.refreshRates(using: service, force: force)
      try Task.checkCancellation()
      warning = result.warning
      rateIssue = result.warning.map(HomeIssue.rateWarning)
      changed(); WidgetCenter.shared.reloadAllTimelines()
      return result
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      guard !Task.isCancelled else { throw CancellationError() }
      rateIssue = .rateSaveFailed
      changed()
      throw error
    }
  }
  var home: HomeDependencies {
    HomeDependencies(
      readInput: conversion.input, readRates: rates.loadRates,
      readRateIssue: { [self] in rateIssue },
      readLocalCurrency: { [local] in (local.widgetLocation(), local.widgetLocationStatus()) },
      editInput: { [self] in try edit($0) },
      refreshRates: { [self] in try await refresh(force: $0) },
      changes: { [self] in changes() })
  }
  var onboarding: OnboardingDependencies {
    OnboardingDependencies(
      loadProgress: progress.load, saveProgress: progress.save,
      readInput: conversion.input, editInput: { [self] mutation in _ = try edit(mutation) },
      readRates: rates.loadRates,
      saveRates: { [self] snapshot, date in
        let result = try rates.saveBootstrapRates(snapshot, now: date)
        changed(); WidgetCenter.shared.reloadAllTimelines(); return result
      },
      bootstrap: { [service] previous, now in await service.bootstrap(previous: previous, now: now)
      },
      now: { .now })
  }
  var details: CurrencyDetailsDependencies {
    CurrencyDetailsDependencies(loadHistory: { [history] code, quote, range in
      await history.load(base: code, quote: quote, range: range)
    })
  }
  private var settingsState: SettingsRateState {
    let input = conversion.input()
    return SettingsRateState(
      snapshot: rates.loadRates(), codes: [input.source] + input.destinations, warning: warning)
  }
  func settings(scene: CurrencyScene) -> SettingsDependencies {
    SettingsDependencies(
      readState: { [self] in settingsState }, changes: { [self] in changes() },
      readPreferences: { [appearance] in
        .init(
          theme: SettingsTheme(rawValue: appearance.theme.rawValue) ?? .system,
          accent: SettingsAccent(rawValue: appearance.accent.rawValue) ?? .primary)
      },
      setTheme: { [appearance] in appearance.theme = .init(rawValue: $0.rawValue) ?? .system },
      setAccent: { [appearance] in appearance.accent = .init(rawValue: $0.rawValue) ?? .primary },
      refresh: { [self] in
        _ = try await refresh(force: true); return settingsState
      },
      replay: { try scene.restartOnboarding() },
      output: { [self] output in
        if case .manageLocation = output {
          routeLocationPermission(
            status: CLLocationManager().authorizationStatus,
            setUp: { scene.requestLocation(addsToApp: false) }, openSettings: openSettings)
        }
      })
  }
  func makeLocationController() -> LocalCurrencyController {
    LocalCurrencyController(
      store: local,
      reloadWidgets: { [weak self] in
        self?.changed(); WidgetCenter.shared.reloadAllTimelines()
      })
  }
  func location(
    controller: LocalCurrencyController, scene: CurrencyScene, id: UUID
  ) -> LocationOnboardingDependencies {
    LocationOnboardingDependencies(
      readSnapshot: {
        LocationSnapshot(
          phase: Self.phase(controller.phase), message: Self.message(controller.message),
          resolved: controller.resolved,
          region: controller.region.map {
            .init(
              latitude: $0.center.latitude, longitude: $0.center.longitude,
              latitudeDelta: $0.span.latitudeDelta, longitudeDelta: $0.span.longitudeDelta)
          }, isUpdating: controller.isUpdating, permissionDenied: controller.permissionDenied,
          permissionRestricted: controller.permissionRestricted,
          permissionAuthorized: controller.permissionAuthorized,
          servicesDisabled: controller.servicesDisabled)
      }, reconcile: controller.reconcileAuthorization, update: controller.update,
      cancel: controller.cancel,
      addResolvedCurrency: { [self] in
        _ = try edit { $0.setUsesLocalCurrency(true) }
      }, now: { .now },
      output: { [self] output in
        switch output {
        case .openSettings: openSettings()
        case .completed, .cancelled: scene.finishLocation(id: id); changed()
        }
      })
  }
  func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
  private static func phase(_ value: LocalCurrencyController.Phase) -> LocationSnapshot.Phase {
    switch value {
    case .introduction: .introduction
    case .requestingPermission: .requestingPermission
    case .locating: .locating
    case .ready: .ready
    case .unavailable: .unavailable
    }
  }
  private static func message(_ value: LocalCurrencyController.Message) -> LocationSnapshot.Message
  {
    switch value {
    case .initial: .initial
    case .finding: .finding
    case .saved: .saved
    case .removed: .removed
    case .permissionDenied: .permissionDenied
    case .permissionRestricted: .permissionRestricted
    case .servicesDisabled: .servicesDisabled
    case .unavailable: .unavailable
    case .unsupported: .unsupported
    case .removeFailed: .removeFailed
    case .updateFailed: .updateFailed
    }
  }
}

private enum AppGroup {
  static var directory: URL {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.com.dimasike.currency")
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Currency")
  }
}
