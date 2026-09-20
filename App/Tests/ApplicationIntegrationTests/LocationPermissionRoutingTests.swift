import CoreLocation
import Testing

@MainActor
@Suite struct LocationPermissionRoutingTests {
  @Test func onlyUnrequestedPermissionOpensSetup() {
    for status: CLAuthorizationStatus in [
      .notDetermined, .denied, .restricted, .authorizedAlways, .authorizedWhenInUse
    ] {
      var setups = 0
      var settings = 0
      routeLocationPermission(
        status: status, setUp: { setups += 1 }, openSettings: { settings += 1 })
      #expect(setups == (status == .notDetermined ? 1 : 0))
      #expect(settings == (status == .notDetermined ? 0 : 1))
    }
  }
}
