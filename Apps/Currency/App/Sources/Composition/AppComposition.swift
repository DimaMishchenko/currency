import AppIntents
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

@MainActor
final class AppComposition {
  let rates: RateStore
  let conversion: ConversionStore
  let local: LocalCurrencyStore
  let progress: OnboardingProgressStore
  let discovery: HomeDiscoveryStore
  let history: HistoryService
  let service = RateService()
  let appearance: AppearancePreferences
  let systemActions: SystemActionComposition
  lazy var searchIndex = CurrencySearchIndex.live(composition: systemActions)
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

  init(
    directory: URL = AppGroup.directory, appearance: AppearancePreferences? = nil,
    discoveryDefaults: UserDefaults = .standard
  ) {
    self.appearance = appearance ?? AppearancePreferences(defaults: .standard)
    rates = RateStore(directory: directory)
    conversion = ConversionStore(directory: directory)
    local = LocalCurrencyStore(directory: directory)
    progress = OnboardingProgressStore(directory: directory)
    discovery = HomeDiscoveryStore(defaults: discoveryDefaults)
    history = HistoryService(directory: directory)
    systemActions = SystemActionComposition(directory: directory, service: service)
    let actions = systemActions
    AppDependencyManager.shared.add(dependency: actions)
    let index = searchIndex
    AppDependencyManager.shared.add(dependency: index)
  }
  func makeScene() -> CurrencyScene {
    CurrencyScene(
      completed: progress.load().map { $0.version == 1 && $0.completed } == true,
      replay: { [self] in
        try progress.restart(input: conversion.input())
      },
      openCurrency: { [self] id in
        let input = conversion.input()
        guard id == CurrencySelection.localID || CurrencyCode(rawValue: id) != nil else {
          return nil
        }
        let (location, status) = systemActions.readLocal()
        let resolved = ResolvedCurrencySelection(codes: [id], location: location, status: status)
        guard let code = id == CurrencySelection.localID ? resolved.localCode : id else {
          return nil
        }
        return HomeDetailsRequest(
          selectionID: id, code: code, reference: input.source, snapshot: rates.loadRates())
      })
  }
  func changed() {
    for observer in observers.values { observer.yield(()) }
    searchIndex.reconcile()
  }
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
      readLocalCurrency: local.snapshot,
      editInput: { [self] in try edit($0) },
      refreshRates: { [self] in try await refresh(force: $0) },
      changes: { [self] in changes() },
      readDiscovery: { [discovery] in discovery.load() },
      saveDiscovery: { [discovery] in discovery.save($0) },
      onboardingCompleted: { [progress] in progress.load()?.completed == true },
      now: { .now })
  }
  func markDetailsVisited() {
    var value = discovery.load()
    value.visitedDetails = true
    discovery.save(value)
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
          phase: controller.phase, outcome: controller.outcome,
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

}

enum AppGroup {
  enum ResolutionError: Error, Equatable { case missingEntitlement }
  static func resolve(using container: (String) -> URL?) throws -> URL {
    guard let directory = container("group.com.dimasike.currency.shared") else {
      throw ResolutionError.missingEntitlement
    }
    return directory
  }
  static var directory: URL {
    do { return try resolve(using: FileManager.default.containerURL) } catch {
      preconditionFailure("Currency requires its configured App Group entitlement: \(error)")
    }
  }
}
