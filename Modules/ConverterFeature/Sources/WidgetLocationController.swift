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
  private let timeoutDuration: Duration

  init(
    manager: CLLocationManager = CLLocationManager(), store: CurrencyStore = .shared,
    timeoutDuration: Duration = .seconds(20)
  ) {
    self.timeoutDuration = timeoutDuration
    self.manager = manager
    self.store = store
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    if store.widgetLocationStatus().allowsCache,
      let location = store.widgetLocation(), location.isUsable
    {
      status = .Converter.localSaved(location.currency, location.country)
    }
  }

  var permissionDenied: Bool { manager.authorizationStatus == .denied }

  func update() {
    guard !isUpdating else { return }
    isUpdating = true
    status = .Converter.localFinding
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
    } else {
      requestIfAuthorized()
    }
  }

  func clear(
    status message: LocalizedStringResource = .Converter.localRemoved,
    outcome: WidgetLocationStatus = .removed
  ) {
    request?.cancel()
    request = nil
    timeout?.cancel()
    timeout = nil
    manager.stopUpdatingLocation()
    isUpdating = false
    do {
      try store.saveWidgetLocationStatus(outcome)
      try store.saveWidgetLocation(nil)
      status = message
      WidgetCenter.shared.reloadAllTimelines()
    } catch { status = .Converter.localRemoveFailed }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
      clear(
        status: permissionStatus,
        outcome: manager.authorizationStatus == .restricted ? .restricted : .denied)
    } else if manager.authorizationStatus == .notDetermined {
      if !isUpdating || timeout != nil || store.widgetLocationStatus().allowsCache {
        reconcileAuthorization()
      }
    } else if isUpdating {
      requestIfAuthorized()
    }
  }

  private func requestIfAuthorized() {
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      guard timeout == nil else { return }
      let duration = timeoutDuration
      timeout = Task { [weak self] in
        try? await Task.sleep(for: duration)
        guard !Task.isCancelled else { return }
        self?.finish(.Converter.localUnavailable)
      }
      manager.requestLocation()
    case .denied, .restricted:
      clear(
        status: permissionStatus,
        outcome: manager.authorizationStatus == .restricted ? .restricted : .denied)
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
        guard
          manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
        else {
          reconcileAuthorization()
          return
        }
        guard let country = items.first?.addressRepresentations?.region?.identifier,
          let currency = WidgetLocation.currency(for: country)
        else {
          finish(.Converter.localUnsupported)
          return
        }
        try store.saveWidgetLocation(
          WidgetLocation(country: country, currency: currency))
        try store.saveWidgetLocationStatus(.available)
        WidgetCenter.shared.reloadAllTimelines()
        finish(.Converter.localSaved(currency, country), succeeded: true)
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

  private func finish(_ message: LocalizedStringResource, succeeded: Bool = false) {
    timeout?.cancel()
    timeout = nil
    request?.cancel()
    request = nil
    manager.stopUpdatingLocation()
    isUpdating = false
    status = message
    if !succeeded {
      do { try store.saveWidgetLocationStatus(.failed) } catch {
        status = .Converter.localUpdateFailed
      }
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  /// Reconcile permission on foreground return without starting a location request.
  func reconcileAuthorization() {
    if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
      clear(
        status: permissionStatus,
        outcome: manager.authorizationStatus == .restricted ? .restricted : .denied)
    } else if manager.authorizationStatus == .notDetermined {
      guard store.widgetLocationStatus() != .removed else { return }
      clear(status: .Converter.localInitial, outcome: .notDetermined)
    } else if [.denied, .restricted].contains(store.widgetLocationStatus()) {
      try? store.saveWidgetLocationStatus(.notDetermined)
      status = .Converter.localInitial
      WidgetCenter.shared.reloadAllTimelines()
    }
  }
}
