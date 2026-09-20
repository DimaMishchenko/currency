#if os(iOS)
  import CoreLocation
  import MapKit
  import Observation

  /// One-shot coarse location shared by app setup, foreground refresh, and widget timelines.
  @MainActor @Observable
  public final class LocalCurrencyController: NSObject, @preconcurrency CLLocationManagerDelegate {
    /// The current setup or refresh phase.
    public enum Phase: Equatable {
      case introduction, requestingPermission, locating, ready, unavailable
    }
    /// Resource-independent result, localized by the feature presenting it.
    public enum Message: Equatable {
      case initial, finding, saved, removed, permissionDenied, permissionRestricted
      case servicesDisabled, unavailable, unsupported, removeFailed, updateFailed
    }
    /// The current phase.
    public var phase: Phase = .introduction
    /// A successfully resolved observation.
    public var resolved: WidgetLocation?
    /// A broad map region exists only after a fresh, authorized lookup succeeds.
    public var region: MKCoordinateRegion?
    /// Whether system location services are disabled.
    public var servicesDisabled = false
    private let servicesEnabled: (() -> Bool)?
    private var availability: Task<Void, Never>?
    private var mayRequestLocation = false
    private let countryLookup: (@MainActor (CLLocation) async throws -> String?)?
    private let reloadWidgets: () -> Void
    /// The current result or recovery reason.
    public var message: Message = .initial
    /// Whether permission or location work is in flight.
    public var isUpdating = false
    private let manager: CLLocationManager
    private let store: LocalCurrencyStore
    private var request: MKReverseGeocodingRequest?
    private var timeout: Task<Void, Never>?
    private let timeoutDuration: Duration
    private var generation: UUID?

    /// Creates a controller without requesting permission or location.
    public init(
      manager: CLLocationManager = CLLocationManager(), store: LocalCurrencyStore,
      timeoutDuration: Duration = .seconds(20),
      servicesEnabled: (() -> Bool)? = nil,
      countryLookup: (@MainActor (CLLocation) async throws -> String?)? = nil,
      reloadWidgets: @escaping () -> Void
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
        message = .saved
        if manager.authorizationStatus == .authorizedWhenInUse
          || manager.authorizationStatus == .authorizedAlways
        {
          resolved = location
          phase = .ready
        }
      }
    }

    /// Whether system policy restricts location access.
    public var permissionRestricted: Bool { manager.authorizationStatus == .restricted }
    /// Whether foreground location access has been granted.
    public var permissionAuthorized: Bool {
      manager.authorizationStatus == .authorizedWhenInUse
        || manager.authorizationStatus == .authorizedAlways
    }
    /// Whether the system supplies reduced-accuracy coordinates.
    public var approximate: Bool { manager.accuracyAuthorization == .reducedAccuracy }
    /// Whether the user denied location access.
    public var permissionDenied: Bool { manager.authorizationStatus == .denied }

    /// Starts an explicit lookup, requesting foreground permission only if needed.
    public func update(requestPermission: Bool = true) {
      guard !isUpdating else { return }
      guard requestPermission || permissionAuthorized else {
        reconcileAuthorization()
        return
      }
      isUpdating = true
      mayRequestLocation = false
      phase = manager.authorizationStatus == .notDetermined ? .requestingPermission : .locating
      message = .finding
      checkServices { [weak self] enabled in
        guard let self, self.isUpdating else { return }
        self.servicesDisabled = !enabled
        guard enabled else {
          self.isUpdating = false
          self.phase = .unavailable
          self.message = .servicesDisabled
          return
        }
        self.mayRequestLocation = true
        self.region = nil
        self.resolved = nil
        if self.manager.authorizationStatus == .notDetermined {
          if requestPermission {
            self.manager.requestWhenInUseAuthorization()
          } else {
            self.cancel(); self.reconcileAuthorization()
          }
        } else {
          self.requestIfAuthorized()
        }
      }
    }

    /// Refreshes at most daily after success, with hourly retries after failure. Never prompts.
    public func refreshIfNeeded(now: Date = .now) async {
      guard !Task.isCancelled else { return }
      reconcileAuthorization()
      guard permissionAuthorized, store.widgetLocationStatus() != .removed else { return }
      if !isUpdating {
        guard (try? store.claimLocalCurrencyRefresh(now: now)) == true else { return }
        update(requestPermission: false)
      }
      while isUpdating {
        do { try await Task.sleep(for: .milliseconds(100)) } catch { cancel(); return }
      }
    }

    /// Refreshes an eligible widget without requesting permission or altering app-only denial state.
    public func refreshForWidget() async {
      let eligibility = CLLocationManager()
      guard eligibility.isAuthorizedForWidgetUpdates else { return }
      await refreshIfNeeded()
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

    /// Clears the observation and cancels outstanding callbacks.
    public func clear(
      status message: Message = .removed,
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
        try store.clearLocalCurrency(outcome: outcome)
        self.message = message
        reloadWidgets()
      } catch { self.message = .removeFailed }
    }

    /// Reconciles permission callbacks and resumes an explicitly started request.
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
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
        do { generation = try store.beginLocalCurrencyLookup() } catch {
          isUpdating = false
          phase = .unavailable
          message = .updateFailed
          return
        }
        phase = .locating
        let duration = timeoutDuration
        timeout = Task { [weak self] in
          try? await Task.sleep(for: duration)
          guard !Task.isCancelled else { return }
          self?.finish(.unavailable)
        }
        manager.requestLocation()
      case .denied, .restricted:
        clear(
          status: permissionStatus,
          outcome: manager.authorizationStatus == .restricted ? .restricted : .denied)
      default: break
      }
    }

    private var permissionStatus: Message {
      manager.authorizationStatus == .restricted
        ? .permissionRestricted : .permissionDenied
    }

    /// Validates a current coordinate and resolves only its country and currency.
    public func locationManager(
      _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
      guard isUpdating, mayRequestLocation, permissionAuthorized, request == nil else { return }
      guard let location = locations.last, location.horizontalAccuracy >= 0,
        abs(location.timestamp.timeIntervalSinceNow) < 300,
        let request = MKReverseGeocodingRequest(location: location)
      else {
        finish(.unavailable)
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
            finish(.unsupported)
            return
          }
          guard let generation,
            try store.completeLocalCurrencyLookup(
              generation, location: WidgetLocation(country: country, currency: currency))
          else {
            cancel()
            adoptSavedObservation()
            return
          }
          resolved = store.widgetLocation()
          // Deliberately omit a location dot and exact coordinates from the presentation.
          region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
              latitude: location.coordinate.latitude.rounded(),
              longitude: location.coordinate.longitude.rounded()),
            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8))
          reloadWidgets()
          finish(.saved, succeeded: true)
        } catch {
          guard isUpdating, self.request === request else { return }
          finish(.unavailable)
        }
      }
    }

    /// Ends a failed lookup while preserving any usable last-known observation.
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
      guard isUpdating else { return }
      finish(.unavailable)
    }

    private func finish(_ message: Message, succeeded: Bool = false) {
      timeout?.cancel()
      timeout = nil
      availability?.cancel()
      availability = nil
      request?.cancel()
      request = nil
      manager.stopUpdatingLocation()
      isUpdating = false
      mayRequestLocation = false
      self.message = message
      phase = succeeded ? .ready : .unavailable
      if !succeeded {
        do {
          if let generation, try !store.completeLocalCurrencyLookup(generation, location: nil) {
            adoptSavedObservation()
          }
        } catch {
          self.message = .updateFailed
        }
        reloadWidgets()
      }
    }

    private func adoptSavedObservation() {
      guard permissionAuthorized, store.widgetLocationStatus() == .available,
        let saved = store.widgetLocation(), saved.isFresh()
      else { return }
      if saved != resolved { region = nil }
      resolved = saved
      phase = .ready
      message = .saved
    }

    /// Dismissing the flow cancels pending work; a late geocoder cannot save a result.
    public func cancel() {
      availability?.cancel(); availability = nil
      request?.cancel(); request = nil
      timeout?.cancel(); timeout = nil
      manager.stopUpdatingLocation()
      if isUpdating {
        phase = .introduction
        message = .initial
      }
      isUpdating = false
      mayRequestLocation = false
      generation = nil
    }

    /// Reconcile permission on foreground return without starting a location request.
    public func reconcileAuthorization() {
      if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
        clear(
          status: permissionStatus,
          outcome: manager.authorizationStatus == .restricted ? .restricted : .denied)
      } else if manager.authorizationStatus == .notDetermined {
        if isUpdating && timeout == nil && request == nil { return }
        if store.widgetLocationStatus() != .removed {
          clear(status: .initial, outcome: .notDetermined)
        }
      } else if [.denied, .restricted].contains(store.widgetLocationStatus()) {
        try? store.saveWidgetLocationStatus(.notDetermined)
        message = .initial
        phase = .introduction
        reloadWidgets()
      }
      guard !isUpdating else { return }
      adoptSavedObservation()
      checkServices { [weak self] enabled in
        guard let self, !self.isUpdating else { return }
        let wasDisabled = self.servicesDisabled
        self.servicesDisabled = !enabled
        if !enabled {
          self.phase = .unavailable
          self.message = .servicesDisabled
          self.resolved = nil
          self.region = nil
        }
        if wasDisabled && enabled && self.permissionAuthorized {
          self.phase = .introduction
          self.message = .initial
        }
      }
    }
  }
#endif
