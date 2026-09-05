import CoreLocation
import CurrencySupport
import MapKit
import Observation
import WidgetKit

/// Requests one coarse foreground location only after the user taps Update.
@MainActor @Observable
final class WidgetLocationController: NSObject, @preconcurrency CLLocationManagerDelegate {
  var status: LocalizedStringResource = .Converter.localInitial
  var isUpdating = false
  private let manager: CLLocationManager
  private let store: CurrencyStore
  private var request: MKReverseGeocodingRequest?
  private var timeout: Task<Void, Never>?

  init(manager: CLLocationManager = CLLocationManager(), store: CurrencyStore = .shared) {
    self.manager = manager
    self.store = store
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    if let location = store.widgetLocation(), location.isFresh() {
      status = .Converter.localSaved(location.currency, location.country)
    }
  }

  func update() {
    guard !isUpdating else { return }
    do {
      try store.saveWidgetLocation(nil)
      WidgetCenter.shared.reloadAllTimelines()
    } catch {
      status = .Converter.localUpdateFailed
      return
    }
    isUpdating = true
    status = .Converter.localFinding
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
    } else {
      requestIfAuthorized()
    }
  }

  func clear(status message: LocalizedStringResource = .Converter.localRemoved) {
    request?.cancel()
    request = nil
    timeout?.cancel()
    timeout = nil
    manager.stopUpdatingLocation()
    isUpdating = false
    do {
      try store.saveWidgetLocation(nil)
      status = message
      WidgetCenter.shared.reloadAllTimelines()
    } catch { status = .Converter.localRemoveFailed }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
      clear(status: permissionStatus)
    } else if isUpdating {
      requestIfAuthorized()
    }
  }

  private func requestIfAuthorized() {
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      guard timeout == nil else { return }
      timeout = Task { [weak self] in
        try? await Task.sleep(for: .seconds(20))
        guard !Task.isCancelled else { return }
        self?.finish(.Converter.localUnavailable)
      }
      manager.requestLocation()
    case .denied, .restricted: clear(status: permissionStatus)
    default: break
    }
  }

  private var permissionStatus: LocalizedStringResource {
    manager.authorizationStatus == .restricted
      ? .Converter.localPermissionRestricted : .Converter.localPermissionDenied
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard isUpdating else { return }
    guard let location = locations.last, location.horizontalAccuracy >= 0,
      abs(location.timestamp.timeIntervalSinceNow) < 300,
      let request = MKReverseGeocodingRequest(location: location)
    else {
      finish(.Converter.localUnavailable)
      return
    }
    self.request = request
    Task {
      do {
        let items = try await request.mapItems
        guard isUpdating, self.request === request, !request.isCancelled else { return }
        guard let country = items.first?.addressRepresentations?.region?.identifier,
          let currency = WidgetLocation.currency(for: country)
        else {
          finish(.Converter.localUnsupported)
          return
        }
        try store.saveWidgetLocation(
          WidgetLocation(country: country, currency: currency))
        WidgetCenter.shared.reloadAllTimelines()
        finish(.Converter.localSaved(currency, country))
      } catch {
        guard isUpdating, self.request === request else { return }
        finish(.Converter.localUnavailable)
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard isUpdating else { return }
    finish(.Converter.localUnavailable)
  }

  private func finish(_ message: LocalizedStringResource) {
    timeout?.cancel()
    timeout = nil
    request?.cancel()
    request = nil
    manager.stopUpdatingLocation()
    isUpdating = false
    status = message
  }
}
