import CurrencySupport
import Foundation

// Keep presentation resources out of the controller shared with the widget extension.
typealias WidgetLocationController = LocalCurrencyController

extension LocalCurrencyController {
  var status: LocalizedStringResource {
    switch message {
    case .initial: .LocalCurrency.localInitial
    case .finding: .LocalCurrency.localFinding
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
