import CoreLocation
import CurrencySupport
import Foundation
import Testing

@testable import ConverterFeature

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
    let controller = WidgetLocationController(manager: manager, store: store)
    controller.update()
    #expect(!controller.isUpdating)
    #expect(store.widgetLocation() == nil)
    #expect(
      String(localized: controller.status) == String(localized: .Converter.localPermissionDenied))
    #expect(manager.locationRequests == 0)
    #expect(manager.authorizationRequests == 0)
  }

  @Test func denyingInitialPromptFinishesPendingUpdate() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = LocationManager()
    let controller = WidgetLocationController(
      manager: manager, store: CurrencyStore(directory: directory))
    controller.update()
    #expect(controller.isUpdating)
    #expect(manager.authorizationRequests == 1)
    manager.permission = .denied
    controller.locationManagerDidChangeAuthorization(manager)
    #expect(!controller.isUpdating)
    #expect(
      String(localized: controller.status) == String(localized: .Converter.localPermissionDenied))
  }

  @Test func restrictedPermissionAndLateCallbacksDoNotReportSuccessfulRemoval() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = LocationManager()
    manager.permission = .restricted
    let controller = WidgetLocationController(
      manager: manager, store: CurrencyStore(directory: directory))
    controller.update()
    #expect(
      String(localized: controller.status)
        == String(localized: .Converter.localPermissionRestricted))
    controller.clear()
    controller.locationManager(manager, didUpdateLocations: [])
    controller.locationManager(manager, didFailWithError: CLError(.locationUnknown))
    #expect(!controller.isUpdating)
    #expect(String(localized: controller.status) == String(localized: .Converter.localRemoved))
  }
}
