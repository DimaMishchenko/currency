#if os(iOS)
  import CoreLocation
  import LocalCurrency
  import Foundation
  import Testing

  @MainActor
  struct WidgetLocationTests {
    private final class LocationManager: CLLocationManager {
      var permission: CLAuthorizationStatus = .notDetermined
      var authorizationRequests = 0
      var locationRequests = 0
      override var authorizationStatus: CLAuthorizationStatus { permission }
      override func requestWhenInUseAuthorization() { authorizationRequests += 1 }
      override func requestLocation() { locationRequests += 1 }
      override func stopUpdatingLocation() {}
    }

    @Test func deniedUpdateClearsCacheAndExplainsHowToEnablePermission() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = LocalCurrencyStore(directory: directory)
      try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      let manager = LocationManager()
      manager.permission = .denied
      let controller = LocalCurrencyController(
        manager: manager, store: store, servicesEnabled: { true }, reloadWidgets: {})
      controller.update()
      #expect(!controller.isUpdating)
      #expect(store.widgetLocation() == nil)
      #expect(
        controller.message == .permissionDenied)
      #expect(manager.locationRequests == 0)
      #expect(manager.authorizationRequests == 0)
    }

    @Test func authorizedFailurePreservesLastKnownAndClearCancelsLateCallbacks() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = LocalCurrencyStore(directory: directory)
      let cached = WidgetLocation(country: "CZ", currency: "CZK", updatedAt: .distantPast)
      try store.saveWidgetLocation(cached)
      let manager = LocationManager()
      manager.permission = .authorizedWhenInUse
      let controller = LocalCurrencyController(
        manager: manager, store: store, servicesEnabled: { true }, reloadWidgets: {})
      controller.update()
      #expect(store.widgetLocation() == cached)
      controller.locationManager(manager, didFailWithError: CLError(.locationUnknown))
      #expect(store.widgetLocation() == cached)
      #expect(store.widgetLocationStatus() == .failed)
      #expect(!controller.isUpdating)
      controller.update()
      controller.clear()
      controller.locationManager(manager, didUpdateLocations: [])
      controller.locationManager(manager, didFailWithError: CLError(.locationUnknown))
      #expect(store.widgetLocation() == nil)
      #expect(store.widgetLocationStatus() == .removed)
    }

    @Test func authorizedTimeoutWithoutCacheAndPermissionReturnRequireExplicitRetry() async throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = LocalCurrencyStore(directory: directory)
      let manager = LocationManager()
      manager.permission = .authorizedWhenInUse
      let controller = LocalCurrencyController(
        manager: manager, store: store, timeoutDuration: .milliseconds(10),
        servicesEnabled: { true }, reloadWidgets: {})
      controller.update()
      try await Task.sleep(for: .milliseconds(100))
      #expect(!controller.isUpdating)
      #expect(store.widgetLocation() == nil)
      #expect(store.widgetLocationStatus() == .failed)
      manager.permission = .denied
      controller.reconcileAuthorization()
      #expect(store.widgetLocationStatus() == .denied)
      manager.permission = .authorizedWhenInUse
      controller.reconcileAuthorization()
      #expect(store.widgetLocationStatus() == .notDetermined)
      #expect(manager.locationRequests == 1)
      controller.clear()
      manager.permission = .notDetermined
      controller.reconcileAuthorization()
      #expect(store.widgetLocationStatus() == .removed)
    }

    @Test func expiredAllowOnceClearsSavedObservationAndIgnoresLateCallbacks() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = LocalCurrencyStore(directory: directory)
      try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      try store.saveWidgetLocationStatus(.available)
      let manager = LocationManager()
      manager.permission = .authorizedWhenInUse
      let controller = LocalCurrencyController(
        manager: manager, store: store, servicesEnabled: { true }, reloadWidgets: {})
      controller.update()
      #expect(controller.isUpdating)
      manager.permission = .notDetermined
      controller.locationManagerDidChangeAuthorization(manager)
      #expect(!controller.isUpdating)
      #expect(store.widgetLocationStatus() == .notDetermined)
      #expect(store.widgetLocation() == nil)
      controller.locationManager(manager, didUpdateLocations: [])
      #expect(store.widgetLocation() == nil)
      controller.update()
      #expect(manager.authorizationRequests == 1)
    }

    @Test func denyingInitialPromptFinishesPendingUpdate() {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let manager = LocationManager()
      let controller = LocalCurrencyController(
        manager: manager, store: LocalCurrencyStore(directory: directory),
        servicesEnabled: { true }, reloadWidgets: {})
      controller.update()
      #expect(controller.isUpdating)
      #expect(manager.authorizationRequests == 1)
      manager.permission = .denied
      controller.locationManagerDidChangeAuthorization(manager)
      #expect(!controller.isUpdating)
      #expect(
        controller.message == .permissionDenied)
    }

    @Test func restrictedPermissionAndLateCallbacksDoNotReportSuccessfulRemoval() {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let manager = LocationManager()
      manager.permission = .restricted
      let controller = LocalCurrencyController(
        manager: manager, store: LocalCurrencyStore(directory: directory),
        servicesEnabled: { true }, reloadWidgets: {})
      controller.update()
      #expect(
        controller.message == .permissionRestricted)
      controller.clear()
      controller.locationManager(manager, didUpdateLocations: [])
      controller.locationManager(manager, didFailWithError: CLError(.locationUnknown))
      #expect(!controller.isUpdating)
      #expect(controller.message == .removed)
    }

    @Test func automaticRefreshNeverPromptsAndSkipsFreshObservation() async throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = LocalCurrencyStore(directory: directory)
      let manager = LocationManager()
      let controller = LocalCurrencyController(
        manager: manager, store: store, servicesEnabled: { true }, reloadWidgets: {})
      await controller.refreshIfNeeded()
      #expect(manager.authorizationRequests == 0)
      #expect(manager.locationRequests == 0)
      manager.permission = .authorizedWhenInUse
      try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      try store.saveWidgetLocationStatus(.available)
      await controller.refreshIfNeeded()
      #expect(manager.locationRequests == 0)
    }

    @Test func dailyRefreshTimesOutOnceAndThrottlesRetry() async throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = LocalCurrencyStore(directory: directory)
      try store.saveWidgetLocation(
        WidgetLocation(country: "CZ", currency: "CZK", updatedAt: .distantPast))
      let manager = LocationManager()
      manager.permission = .authorizedWhenInUse
      let controller = LocalCurrencyController(
        manager: manager, store: store, timeoutDuration: .milliseconds(10),
        servicesEnabled: { true }, reloadWidgets: {})
      await controller.refreshIfNeeded()
      #expect(manager.locationRequests == 1)
      #expect(manager.authorizationRequests == 0)
      #expect(store.widgetLocationStatus() == .failed)
      #expect(store.widgetLocation()?.currency == "CZK")
      await controller.refreshIfNeeded()
      #expect(manager.locationRequests == 1)
    }

    @Test func olderControllerFailureCannotMarkNewerSuccessfulLookupFailed() async throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = LocalCurrencyStore(directory: directory)
      let firstManager = LocationManager()
      firstManager.permission = .authorizedWhenInUse
      let secondManager = LocationManager()
      secondManager.permission = .authorizedWhenInUse
      let first = LocalCurrencyController(
        manager: firstManager, store: store, servicesEnabled: { true }, reloadWidgets: {})
      let second = LocalCurrencyController(
        manager: secondManager, store: store, servicesEnabled: { true },
        countryLookup: { _ in "GB" }, reloadWidgets: {})
      first.update()
      second.update()
      second.locationManager(
        secondManager, didUpdateLocations: [CLLocation(latitude: 51.5, longitude: -0.1)])
      for _ in 0..<100 where second.isUpdating { try await Task.sleep(for: .milliseconds(2)) }
      #expect(second.phase == .ready)
      first.locationManager(firstManager, didFailWithError: CLError(.locationUnknown))
      #expect(store.widgetLocation()?.currency == "GBP")
      #expect(store.widgetLocationStatus() == .available)
      first.cancel()
      second.cancel()
    }
  }

#endif
