import CurrencySupport
import Foundation

/// Canonical widget configuration plus its resolved local-currency presentation.
public struct WidgetSpec: Sendable {
  /// Stable WidgetKit kind used by persistence and reloads.
  public var kind: String
  /// Resolved display codes, including any resolved Local slot.
  public var codes: [String]
  /// Configured initial or reference amount.
  public var amount = "1"
  /// Latest permission and lookup outcome.
  public var locationStatus: WidgetLocationStatus = .notDetermined
  /// Usable cached local currency, when one exists.
  public var localCode: String?
  /// Whether the cached local observation needs an explicit update.
  public var localIsStale = false
  /// Full configured list; never truncated for a widget size.
  public var canonicalCodes: [String]
  /// Whether the configuration includes a Local slot.
  public var usesLocation: Bool { canonicalCodes.contains(WidgetSelection.localID) }
  /// WidgetKit-provided identity for independently editable instances.
  public var instanceID: String?
  /// Whether interactive values follow the app and reserve a Local slot.
  public var synchronized = false
  /// Whether the native editor still needs a Custom list.
  public var requiresCurrencySelection = false
  /// Stable storage key derived from canonical configuration and instance identity.
  public var key: String {
    if let instanceID {
      return "\(kind)|instance|\(instanceID)|\(synchronized ? "default" : "custom")"
    }
    return ([kind] + canonicalCodes).joined(separator: "|")
  }

  /// Resolves canonical codes using the supplied observation and permission status.
  /// Pass `status` explicitly for isolated previews; production defaults to the shared cache status.
  public init(
    kind: String, codes: [String], amount: String = "1",
    local: Bool = false, location: CurrencySupport.WidgetLocation? = nil, instanceID: String? = nil,
    status: WidgetLocationStatus? = nil
  ) {
    self.kind = kind
    var configured = codes
    if local, !configured.contains(WidgetSelection.localID) {
      if configured.count > 1 {
        configured[1] = WidgetSelection.localID
      } else {
        configured.append(WidgetSelection.localID)
      }
    }
    locationStatus = status ?? CurrencyStore.shared.widgetLocationStatus()
    let resolved = WidgetResolvedSelection(
      codes: configured, location: location, status: locationStatus)
    canonicalCodes = resolved.canonical
    self.codes = resolved.codes
    localCode = resolved.localCode
    localIsStale = resolved.localIsStale
    self.instanceID = instanceID
    self.amount = amount

  }
}
