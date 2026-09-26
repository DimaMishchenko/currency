import Foundation
import LocationOnboarding

extension LocationSnapshot {
  var status: LocalizedStringResource {
    switch outcome {
    case .none: .LocalCurrency.localInitial
    case .saved: .LocalCurrency.localSaved(resolved?.currency ?? "", resolved?.country ?? "")
    case .removed: .LocalCurrency.localRemoved
    case .permissionDenied: .LocalCurrency.localPermissionDenied
    case .permissionRestricted: .LocalCurrency.localPermissionRestricted
    case .servicesDisabled: .LocalCurrency.localServicesDisabled
    case .unavailable: .LocalCurrency.localUnavailable
    case .unsupported: .LocalCurrency.localUnsupported
    case .removeFailed: .LocalCurrency.localRemoveFailed
    case .updateFailed: .LocalCurrency.localUpdateFailed
    }
  }
}
