import Foundation
import LocalCurrency
import Observation

/// Feature-owned projection of a coarse region; MapKit stays at the UI boundary.
public struct LocationMapRegion: Sendable, Equatable {
  /// Center latitude in degrees.
  public let latitude: Double
  /// Center longitude in degrees.
  public let longitude: Double
  /// Latitude span in degrees.
  public let latitudeDelta: Double
  /// Longitude span in degrees.
  public let longitudeDelta: Double
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(latitude: Double, longitude: Double, latitudeDelta: Double, longitudeDelta: Double) {
    self.latitude = latitude; self.longitude = longitude
    self.latitudeDelta = latitudeDelta; self.longitudeDelta = longitudeDelta
  }
}

/// An owned projection of permission, lookup progress, and coarse location.
public struct LocationSnapshot: Sendable {
  /// Mutually exclusive stages of a location lookup.
  public enum Phase: Sendable, Equatable {
    case introduction, requestingPermission, locating, ready, unavailable
  }
  /// Resource-independent lookup outcome or recovery reason.
  public enum Message: Sendable, Equatable {
    case initial, finding, saved, removed, permissionDenied, permissionRestricted
    case servicesDisabled, unavailable, unsupported, removeFailed, updateFailed
  }
  /// Current location lookup stage.
  public var phase: Phase
  /// Current lookup outcome or recovery reason.
  public var message: Message
  /// Coarse country and currency observation, when available.
  public var resolved: WidgetLocation?
  /// Optional coarse map region; never raw device coordinates.
  public var region: LocationMapRegion?
  /// Whether permission or location lookup is in flight.
  public var isUpdating: Bool
  /// Whether the user denied location access.
  public var permissionDenied: Bool
  /// Whether system policy prevents location access.
  public var permissionRestricted: Bool
  /// Whether foreground location access is available.
  public var permissionAuthorized: Bool
  /// Whether system location services are disabled.
  public var servicesDisabled: Bool
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(
    phase: Phase = .introduction, message: Message = .initial, resolved: WidgetLocation? = nil,
    region: LocationMapRegion? = nil, isUpdating: Bool = false,
    permissionDenied: Bool = false, permissionRestricted: Bool = false,
    permissionAuthorized: Bool = false, servicesDisabled: Bool = false
  ) {
    self.phase = phase; self.message = message; self.resolved = resolved; self.region = region
    self.isUpdating = isUpdating; self.permissionDenied = permissionDenied
    self.permissionRestricted = permissionRestricted;
    self.permissionAuthorized = permissionAuthorized
    self.servicesDisabled = servicesDisabled
  }
}

/// Semantic completion and permission-management requests for the host.
public enum LocationOnboardingOutput: Sendable { case completed, cancelled, openSettings }

/// Observation from readSnapshot is forwarded from the host's authoritative capability.
/// update starts one controller-owned operation; cancel ends it on actual flow teardown.
@MainActor
public struct LocationOnboardingDependencies {
  /// Reads the authoritative observable location capability without starting work.
  public var readSnapshot: () -> LocationSnapshot
  /// Reconciles saved observations against current system authorization.
  public var reconcile: () -> Void
  /// Requests one lookup; the Boolean chooses whether permission may be requested.
  public var update: (_ requestPermission: Bool) -> Void
  /// Cancels the host lookup when this flow ends.
  public var cancel: () -> Void
  /// Commits the Local selection to confirmed converter input.
  public var addResolvedCurrency: () throws -> Void
  /// Clock used to evaluate the freshness of a resolved observation.
  public var now: () -> Date
  /// Receives semantic outcomes and requests for application coordination.
  public var output: (LocationOnboardingOutput) -> Void
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(
    readSnapshot: @escaping () -> LocationSnapshot, reconcile: @escaping () -> Void,
    update: @escaping (Bool) -> Void, cancel: @escaping () -> Void,
    addResolvedCurrency: @escaping () throws -> Void, now: @escaping () -> Date,
    output: @escaping (LocationOnboardingOutput) -> Void
  ) {
    self.readSnapshot = readSnapshot; self.reconcile = reconcile; self.update = update
    self.cancel = cancel; self.addResolvedCurrency = addResolvedCurrency
    self.now = now; self.output = output
  }
}

/// Testable permission and confirmation flow, with injected platform operations.
@MainActor @Observable
public final class LocationOnboardingModel {
  private let dependencies: LocationOnboardingDependencies
  /// Whether completion commits the Local selection to confirmed input.
  public let addsResolvedCurrencyToApp: Bool
  /// Whether the last confirmation failed to persist.
  public private(set) var saveFailed = false
  /// Whether the host ended this flow identity.
  public private(set) var stopped = false
  /// The latest supplied rate or location observation.
  public var snapshot: LocationSnapshot { dependencies.readSnapshot() }
  /// Whether a fresh resolved observation can be confirmed.
  public var ready: Bool {
    snapshot.phase == .ready && snapshot.resolved?.isFresh(now: dependencies.now()) == true
  }
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(dependencies: LocationOnboardingDependencies, addsResolvedCurrencyToApp: Bool = false)
  {
    self.dependencies = dependencies
    self.addsResolvedCurrencyToApp = addsResolvedCurrencyToApp
  }
  /// Reconciles foreground authorization and refreshes without prompting when authorized.
  public func refreshLocation() {
    guard !stopped else { return }
    dependencies.reconcile()
    if snapshot.permissionAuthorized && !ready && !snapshot.isUpdating {
      dependencies.update(false)
    }
  }
  /// Requests one lookup; the Boolean chooses whether permission may be requested.
  public func update() {
    guard !stopped, !snapshot.isUpdating else { return }
    dependencies.update(true)
  }
  /// Asks application coordination to open system permission settings.
  public func openSettings() {
    guard !stopped else { return }
    dependencies.output(.openSettings)
  }
  /// Confirms a fresh result, committing input before emitting completion.
  @discardableResult
  public func complete() -> Bool {
    guard !stopped, ready else { return false }
    do {
      if addsResolvedCurrencyToApp { try dependencies.addResolvedCurrency() }
      saveFailed = false
      stop()
      dependencies.output(.completed)
      return true
    } catch { saveFailed = true; return false }
  }
  /// Cancels lookup work and emits the user cancellation outcome.
  public func close() {
    guard !stopped else { return }
    stop(); dependencies.output(.cancelled)
  }
  /// Remains active for the outer entry lifetime; local navigation does not replace this host.
  public func run() async {
    await withTaskCancellationHandler {
      let lifetime = AsyncStream<Void>(bufferingPolicy: .unbounded) { _ in }
      for await _ in lifetime {}
      stop()
    } onCancel: {
      Task { @MainActor [weak self] in self?.stop() }
    }
  }
  /// Ends this flow operation lifetime and rejects results arriving after teardown.
  public func stop() {
    guard !stopped else { return }
    stopped = true
    dependencies.cancel()
  }
}
