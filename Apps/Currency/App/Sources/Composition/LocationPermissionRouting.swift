import CoreLocation

@MainActor
func routeLocationPermission(
  status: CLAuthorizationStatus, setUp: () -> Void, openSettings: () -> Void
) {
  if status == .notDetermined { setUp() } else { openSettings() }
}
