import CoreLocation

/// Maps the current system permission to a user-initiated action without starting a lookup.
@MainActor
func routeLocationPermission(
  status: CLAuthorizationStatus, setUp: () -> Void, openSettings: () -> Void
) {
  if status == .notDetermined { setUp() } else { openSettings() }
}
