import CoreLocation
import CurrencySupport
import MapKit
import Observation
import WidgetKit

/// Requests one coarse foreground location only after the user taps Update.
@MainActor @Observable
final class WidgetLocationController: NSObject, @preconcurrency CLLocationManagerDelegate {
  enum Phase: Equatable { case introduction, requestingPermission, locating, ready, unavailable }
  var phase: Phase = .introduction
  var resolved: CurrencySupport.WidgetLocation?
  /// A broad map region exists only after a fresh, authorized lookup succeeds.
  var region: MKCoordinateRegion?
  var servicesDisabled = false
  private let servicesEnabled: (() -> Bool)?
  private var availability: Task<Void, Never>?
  private var mayRequestLocation = false
  private let countryLookup: (@MainActor (CLLocation) async throws -> String?)?
  private let reloadWidgets: () -> Void
  var status: LocalizedStringResource = .LocalCurrency.localInitial
  var isUpdating = false
  private let manager: CLLocationManager
  private let store: CurrencyStore
  private var request: MKReverseGeocodingRequest?
  private var timeout: Task<Void, Never>?
  private let timeoutDuration: Duration

  init(
    manager: CLLocationManager = CLLocationManager(), store: CurrencyStore = .shared,
    timeoutDuration: Duration = .seconds(20),
    servicesEnabled: (() -> Bool)? = nil,
    countryLookup: (@MainActor (CLLocation) async throws -> String?)? = nil,
    reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
  ) {
    self.countryLookup = countryLookup
    self.reloadWidgets = reloadWidgets
    self.servicesEnabled = servicesEnabled
    self.timeoutDuration = timeoutDuration
    self.manager = manager
    self.store = store
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    if store.widgetLocationStatus() == .available,
      let location = store.widgetLocation(), location.isFresh()
    {
      status = .LocalCurrency.localSaved(location.currency, location.country)
      if manager.authorizationStatus == .authorizedWhenInUse
        || manager.authorizationStatus == .authorizedAlways
      {
        resolved = location
        phase = .ready
      }
    }
  }

  var permissionRestricted: Bool { manager.authorizationStatus == .restricted }
  var permissionAuthorized: Bool {
    manager.authorizationStatus == .authorizedWhenInUse
      || manager.authorizationStatus == .authorizedAlways
  }
  var approximate: Bool { manager.accuracyAuthorization == .reducedAccuracy }
  var permissionDenied: Bool { manager.authorizationStatus == .denied }

  func update() {
    guard !isUpdating else { return }
    isUpdating = true
    mayRequestLocation = false
    phase = manager.authorizationStatus == .notDetermined ? .requestingPermission : .locating
    status = .LocalCurrency.localFinding
    checkServices { [weak self] enabled in
      guard let self, self.isUpdating else { return }
      self.servicesDisabled = !enabled
      guard enabled else {
        self.isUpdating = false
        self.phase = .unavailable
        self.status = .LocalCurrency.localServicesDisabled
        return
      }
      self.mayRequestLocation = true
      self.region = nil
      self.resolved = nil
      if self.manager.authorizationStatus == .notDetermined {
        self.manager.requestWhenInUseAuthorization()
      } else {
        self.requestIfAuthorized()
      }
    }
  }

  /// Service availability may involve IPC; keep that query off the UI thread.
  private func checkServices(_ completion: @escaping @MainActor (Bool) -> Void) {
    availability?.cancel()
    if let servicesEnabled { completion(servicesEnabled()); return }
    availability = Task {
      let enabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
      guard !Task.isCancelled else { return }
      completion(enabled)
    }
  }

  func clear(
    status message: LocalizedStringResource = .LocalCurrency.localRemoved,
    outcome: WidgetLocationStatus = .removed
  ) {
    availability?.cancel()
    availability = nil
    request?.cancel()
    request = nil
    timeout?.cancel()
    timeout = nil
    manager.stopUpdatingLocation()
    isUpdating = false
    mayRequestLocation = false
    resolved = nil
    region = nil
    phase = outcome == .denied || outcome == .restricted ? .unavailable : .introduction
    do {
      try store.saveWidgetLocationStatus(outcome)
      try store.saveWidgetLocation(nil)
      status = message
      reloadWidgets()
    } catch { status = .LocalCurrency.localRemoveFailed }
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
    guard isUpdating, mayRequestLocation else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      guard timeout == nil else { return }
      phase = .locating
      let duration = timeoutDuration
      timeout = Task { [weak self] in
        try? await Task.sleep(for: duration)
        guard !Task.isCancelled else { return }
        self?.finish(.LocalCurrency.localUnavailable)
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
      ? .LocalCurrency.localPermissionRestricted : .LocalCurrency.localPermissionDenied
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard isUpdating, mayRequestLocation, permissionAuthorized, request == nil else { return }
    guard let location = locations.last, location.horizontalAccuracy >= 0,
      abs(location.timestamp.timeIntervalSinceNow) < 300,
      let request = MKReverseGeocodingRequest(location: location)
    else {
      finish(.LocalCurrency.localUnavailable)
      return
    }
    self.request = request
    Task {
      do {
        let country: String?
        if let countryLookup {
          country = try await countryLookup(location)
        } else {
          country = try await request.mapItems.first?.addressRepresentations?.region?.identifier
        }
        guard isUpdating, self.request === request, !request.isCancelled else { return }
        guard
          manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
        else {
          reconcileAuthorization()
          return
        }
        guard let country,
          let currency = WidgetLocation.currency(for: country)
        else {
          finish(.LocalCurrency.localUnsupported)
          return
        }
        try store.saveWidgetLocation(
          WidgetLocation(country: country, currency: currency))
        try store.saveWidgetLocationStatus(.available)
        resolved = store.widgetLocation()
        // Deliberately omit a location dot and exact coordinates from the presentation.
        region = MKCoordinateRegion(
          center: CLLocationCoordinate2D(
            latitude: location.coordinate.latitude.rounded(),
            longitude: location.coordinate.longitude.rounded()),
          span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8))
        reloadWidgets()
        finish(.LocalCurrency.localSaved(currency, country), succeeded: true)
      } catch {
        guard isUpdating, self.request === request else { return }
        finish(.LocalCurrency.localUnavailable)
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard isUpdating else { return }
    finish(.LocalCurrency.localUnavailable)
  }

  private func finish(_ message: LocalizedStringResource, succeeded: Bool = false) {
    timeout?.cancel()
    timeout = nil
    availability?.cancel()
    availability = nil
    request?.cancel()
    request = nil
    manager.stopUpdatingLocation()
    isUpdating = false
    mayRequestLocation = false
    status = message
    phase = succeeded ? .ready : .unavailable
    if !succeeded {
      do { try store.saveWidgetLocationStatus(.failed) } catch {
        status = .LocalCurrency.localUpdateFailed
      }
      reloadWidgets()
    }
  }

  /// Dismissing the flow cancels pending work; a late geocoder cannot save a result.
  func cancel() {
    availability?.cancel(); availability = nil
    request?.cancel(); request = nil
    timeout?.cancel(); timeout = nil
    manager.stopUpdatingLocation()
    if isUpdating {
      phase = .introduction
      status = .LocalCurrency.localInitial
    }
    isUpdating = false
    mayRequestLocation = false
  }

  /// Reconcile permission on foreground return without starting a location request.
  func reconcileAuthorization() {
    if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
      clear(
        status: permissionStatus,
        outcome: manager.authorizationStatus == .restricted ? .restricted : .denied)
    } else if manager.authorizationStatus == .notDetermined {
      if isUpdating && timeout == nil && request == nil { return }
      if store.widgetLocationStatus() != .removed {
        clear(status: .LocalCurrency.localInitial, outcome: .notDetermined)
      }
    } else if [.denied, .restricted].contains(store.widgetLocationStatus()) {
      try? store.saveWidgetLocationStatus(.notDetermined)
      status = .LocalCurrency.localInitial
      phase = .introduction
      reloadWidgets()
    }
    guard !isUpdating else { return }
    checkServices { [weak self] enabled in
      guard let self, !self.isUpdating else { return }
      let wasDisabled = self.servicesDisabled
      self.servicesDisabled = !enabled
      if wasDisabled && enabled && self.permissionAuthorized {
        self.phase = .introduction
        self.status = .LocalCurrency.localInitial
      }
    }
  }
}
