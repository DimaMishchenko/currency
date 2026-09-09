import CoreLocation
import CurrencySupport
import Foundation
import Testing

@testable import LocalCurrencyOnboardingFeature
@testable import WidgetOnboardingFeature

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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
    let manager = LocationManager()
    manager.permission = .denied
    let controller = WidgetLocationController(
      manager: manager, store: store, servicesEnabled: { true })
    controller.update()
    #expect(!controller.isUpdating)
    #expect(store.widgetLocation() == nil)
    #expect(
      String(localized: controller.status) == String(localized: .LocalCurrency.localPermissionDenied))
    #expect(manager.locationRequests == 0)
    #expect(manager.authorizationRequests == 0)
  }

  @Test func authorizedFailurePreservesLastKnownAndClearCancelsLateCallbacks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let cached = WidgetLocation(country: "CZ", currency: "CZK", updatedAt: .distantPast)
    try store.saveWidgetLocation(cached)
    let manager = LocationManager()
    manager.permission = .authorizedWhenInUse
    let controller = WidgetLocationController(
      manager: manager, store: store, servicesEnabled: { true })
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let manager = LocationManager()
    manager.permission = .authorizedWhenInUse
    let controller = WidgetLocationController(
      manager: manager, store: store, timeoutDuration: .milliseconds(10), servicesEnabled: { true })
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
    try store.saveWidgetLocationStatus(.available)
    let manager = LocationManager()
    manager.permission = .authorizedWhenInUse
    let controller = WidgetLocationController(
      manager: manager, store: store, servicesEnabled: { true })
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = LocationManager()
    let controller = WidgetLocationController(
      manager: manager, store: CurrencyStore(directory: directory), servicesEnabled: { true })
    controller.update()
    #expect(controller.isUpdating)
    #expect(manager.authorizationRequests == 1)
    manager.permission = .denied
    controller.locationManagerDidChangeAuthorization(manager)
    #expect(!controller.isUpdating)
    #expect(
      String(localized: controller.status) == String(localized: .LocalCurrency.localPermissionDenied))
  }

  @Test func restrictedPermissionAndLateCallbacksDoNotReportSuccessfulRemoval() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = LocationManager()
    manager.permission = .restricted
    let controller = WidgetLocationController(
      manager: manager, store: CurrencyStore(directory: directory), servicesEnabled: { true })
    controller.update()
    #expect(
      String(localized: controller.status)
        == String(localized: .LocalCurrency.localPermissionRestricted))
    controller.clear()
    controller.locationManager(manager, didUpdateLocations: [])
    controller.locationManager(manager, didFailWithError: CLError(.locationUnknown))
    #expect(!controller.isUpdating)
    #expect(String(localized: controller.status) == String(localized: .LocalCurrency.localRemoved))
  }
}
