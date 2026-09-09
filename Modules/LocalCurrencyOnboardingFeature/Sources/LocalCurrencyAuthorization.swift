import SwiftUI

/// Foreground reconciliation of saved Local currency permission, without starting a lookup.
@MainActor
public enum LocalCurrencyAuthorization {
  /// Removes unusable saved permission state after a Settings change or Allow Once expiry.
  public static func reconcile() {
    WidgetLocationController().reconcileAuthorization()
  }
}
