import CoreLocation
import CurrencySupport
import Foundation
import Testing
import WidgetKit
import WidgetPresentation

@testable import LocalCurrencyOnboardingFeature
@testable import WidgetOnboardingFeature

@MainActor
struct WidgetOnboardingTests {
  private final class LocationManager: CLLocationManager {
    var permission: CLAuthorizationStatus = .notDetermined
    var accuracy: CLAccuracyAuthorization = .reducedAccuracy
    var prompts = 0
    var lookups = 0
    override var authorizationStatus: CLAuthorizationStatus { permission }
    override var accuracyAuthorization: CLAccuracyAuthorization { accuracy }
    override func requestWhenInUseAuthorization() { prompts += 1 }
    override func requestLocation() { lookups += 1 }
    override func stopUpdatingLocation() {}
  }
  private func withStore(_ body: (CurrencyStore) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(CurrencyStore(directory: directory))
  }
  private var coarseLocation: CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 50.08, longitude: 14.43),
      altitude: 0, horizontalAccuracy: 5000, verticalAccuracy: -1, timestamp: .now)
  }
  private func settle(_ controller: WidgetLocationController) async throws {
    for _ in 0..<100 where controller.isUpdating { try await Task.sleep(for: .milliseconds(2)) }
    #expect(!controller.isUpdating)
  }

  @Test func introductionDoesNotRequestLocationOrExposeMap() async throws {
    try await withStore { store in
      let manager = LocationManager()
      let controller = WidgetLocationController(
        manager: manager, store: store, servicesEnabled: { true })
      #expect(controller.phase == .introduction)
      #expect(controller.region == nil)
      #expect(controller.resolved == nil)
      #expect(manager.prompts == 0)
      #expect(manager.lookups == 0)
      controller.update()
      #expect(manager.prompts == 1)
      #expect(manager.lookups == 0)
      #expect(controller.phase == .requestingPermission)
      // Even an unexpected callback cannot start geocoding before permission.
      controller.locationManager(manager, didUpdateLocations: [coarseLocation])
      #expect(controller.region == nil)
      #expect(store.widgetLocation() == nil)
      controller.cancel()
    }
  }

  @Test func authorizationCallbackCannotBypassPendingServicesCheck() async throws {
    try await withStore { store in
      let manager = LocationManager()
      manager.permission = .authorizedWhenInUse
      let controller = WidgetLocationController(manager: manager, store: store)
      controller.update()
      // Production service availability has not returned to the main actor yet.
      controller.locationManagerDidChangeAuthorization(manager)
      controller.locationManager(manager, didUpdateLocations: [coarseLocation])
      #expect(manager.lookups == 0)
      #expect(controller.region == nil)
      #expect(store.widgetLocation() == nil)
      controller.cancel()
      await Task.yield()
      #expect(manager.lookups == 0)
    }
  }

  @Test func failedCacheDoesNotPresentReadyState() async throws {
    try await withStore { store in
      let manager = LocationManager(); manager.permission = .authorizedWhenInUse
      try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      try store.saveWidgetLocationStatus(.failed)
      let failed = WidgetLocationController(
        manager: manager, store: store, servicesEnabled: { true })
      #expect(failed.phase == .introduction)
      #expect(failed.region == nil)
      #expect(failed.resolved == nil)
      try store.saveWidgetLocationStatus(.available)
      let cached = WidgetLocationController(
        manager: manager, store: store, servicesEnabled: { true })
      #expect(cached.phase == .ready)
      #expect(cached.resolved?.currency == "CZK")
      #expect(cached.region == nil)
      #expect(manager.lookups == 0)
    }
  }

  @Test func geocoderFailureKeepsRecoveryAvailable() async throws {
    try await withStore { store in
      let manager = LocationManager(); manager.permission = .authorizedWhenInUse
      let controller = WidgetLocationController(
        manager: manager, store: store, servicesEnabled: { true },
        countryLookup: { _ in throw URLError(.notConnectedToInternet) })
      controller.update()
      controller.locationManager(manager, didUpdateLocations: [coarseLocation])
      try await settle(controller)
      #expect(controller.phase == .unavailable)
      #expect(controller.region == nil)
      #expect(controller.resolved == nil)
      controller.update()
      #expect(manager.lookups == 2)
      controller.cancel()
    }
  }

  @Test func enablingServicesInSettingsOffersExplicitRetry() async throws {
    try await withStore { store in
      var enabled = false
      let manager = LocationManager()
      manager.permission = .authorizedWhenInUse
      let controller = WidgetLocationController(
        manager: manager, store: store, servicesEnabled: { enabled })
      controller.update()
      #expect(controller.servicesDisabled)
      #expect(controller.phase == .unavailable)
      #expect(manager.lookups == 0)
      enabled = true
      controller.reconcileAuthorization()
      #expect(!controller.servicesDisabled)
      #expect(controller.phase == .introduction)
      #expect(manager.lookups == 0)
      controller.update()
      #expect(manager.lookups == 1)
      #expect(manager.prompts == 0)
      controller.cancel()
    }
  }

  @Test func approximateLookupSavesBeforePresentingSuccessAndReloading() async throws {
    try await withStore { store in
      let manager = LocationManager()
      manager.permission = .authorizedWhenInUse
      var reloads = 0
      let controller = WidgetLocationController(
        manager: manager, store: store, servicesEnabled: { true },
        countryLookup: { _ in "CZ" },
        reloadWidgets: {
          #expect(store.widgetLocation()?.currency == "CZK")
          #expect(store.widgetLocationStatus() == .available)
          reloads += 1
        })
      controller.update()
      #expect(manager.prompts == 0)
      #expect(controller.approximate)
      controller.locationManager(manager, didUpdateLocations: [coarseLocation])
      try await settle(controller)
      #expect(controller.phase == .ready)
      #expect(controller.resolved?.currency == "CZK")
      #expect(controller.region?.center.latitude == 50)
      #expect(controller.region?.center.longitude == 14)
      #expect(controller.region?.span.latitudeDelta == 8)
      #expect(reloads == 1)
      // Subsequent callbacks cannot save or reload a second time.
      controller.locationManager(manager, didUpdateLocations: [coarseLocation])
      #expect(reloads == 1)
    }
  }

  @Test func unsupportedLookupKeepsMapAndSuccessHidden() async throws {
    try await withStore { store in
      let manager = LocationManager(); manager.permission = .authorizedWhenInUse
      let controller = WidgetLocationController(
        manager: manager, store: store, servicesEnabled: { true }, countryLookup: { _ in "ZZ" })
      controller.update()
      controller.locationManager(manager, didUpdateLocations: [coarseLocation])
      try await settle(controller)
      #expect(controller.phase == .unavailable)
      #expect(controller.region == nil)
      #expect(controller.resolved == nil)
      #expect(store.widgetLocationStatus() == .failed)
    }
  }

  @Test func cancellationAndPermissionExpiryRejectPendingGeocoder() async throws {
    try await withStore { store in
      let manager = LocationManager(); manager.permission = .authorizedWhenInUse
      let controller = WidgetLocationController(
        manager: manager, store: store, servicesEnabled: { true },
        countryLookup: { _ in
          try await Task.sleep(for: .milliseconds(30)); return "CZ"
        })
      controller.update()
      controller.locationManager(manager, didUpdateLocations: [coarseLocation])
      controller.cancel()
      try await Task.sleep(for: .milliseconds(50))
      #expect(store.widgetLocation() == nil)
      #expect(controller.region == nil)
      controller.update()
      controller.locationManager(manager, didUpdateLocations: [coarseLocation])
      manager.permission = .notDetermined
      controller.reconcileAuthorization()
      try await Task.sleep(for: .milliseconds(50))
      #expect(store.widgetLocation() == nil)
      #expect(controller.phase == .introduction)
    }
  }

  @Test func calculatorPreviewUsesTemporaryCanonicalStateAcrossSizes() {
    var preview = WidgetPreviewState(kind: .calculator)
    var spec = WidgetSpec(kind: "CurrencyConverter", codes: ["EUR", "USD", "GBP", "JPY"])
    // Preview dispatch must remain in memory even when an intent carries Default metadata.
    spec.synchronized = true
    preview.apply(WidgetCommand("7", spec: spec))
    preview.apply(WidgetCommand("5", spec: spec))
    #expect(preview.input.decimal == 75)
    preview.apply(WidgetCommand("select:USD", spec: spec))
    #expect(preview.input.decimal == 81)
    #expect(preview.input.codes == ["EUR", "USD", "GBP", "JPY"])
    _ = preview.input.displayedInput(limit: 2, snapshot: WidgetPreviewState.rates)
    #expect(preview.input.codes.count == 4)
    #expect(WidgetPreviewState(kind: .calculator).input.decimal == 100)
  }
}
