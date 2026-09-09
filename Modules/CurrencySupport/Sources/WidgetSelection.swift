import ExchangeRates
import Foundation

/// Ordered canonical lists are independent of the number of visible widget slots.
public enum WidgetSelection {
  /// Unresolved Local placeholder used in canonical configuration.
  public static let localID = "@local"
  /// Whether a code is an unresolved or resolved Local slot.
  public static func isLocal(_ code: String) -> Bool {
    code == localID || code.hasPrefix("@local:")
  }
  /// Extracts the actual currency code from a resolved Local slot.
  public static func currency(_ code: String) -> String {
    code.hasPrefix("@local:") ? String(code.dropFirst(7)) : code
  }

  /// Preserves valid unique currencies in their original order.
  public static func normalize(_ codes: [String], allowsLocal: Bool = false) -> [String] {
    var seen = Set<String>()
    return codes.filter {
      (CurrencyCatalog.codes.contains($0)
        || (allowsLocal
          && ($0 == localID
            || ($0.hasPrefix("@local:") && CurrencyCatalog.codes.contains(currency($0))))))
        && seen.insert($0).inserted
    }
  }

  /// Returns the app source followed by its unique destination currencies.
  public static func appCurrencies(_ input: ConverterState) -> [String] {
    normalize([input.source] + input.destinations)
  }

  /// Resolves only list ownership; amounts and active input remain widget-specific.
  public static func calculator(
    app: ConverterState, custom: [String]?, usesCustom: Bool, includeLocal: Bool
  ) -> [String] {
    if usesCustom { return normalize(custom ?? [], allowsLocal: true) }
    return normalize(appCurrencies(app) + (includeLocal ? [localID] : []), allowsLocal: true)
  }

  /// Places the board base before its unique target currencies.
  public static func board(base: String, targets: [String]) -> [String] {
    normalize([base] + targets)
  }
}

/// Resolves a local slot without replacing a failed lookup with an arbitrary currency.
public struct WidgetResolvedSelection: Equatable, Sendable {
  /// Complete configured selection, including unresolved Local intent.
  public let canonical: [String]
  /// Display selection with a supported Local observation resolved when available.
  public let codes: [String]
  /// Supported currency from the usable cached country observation.
  public let localCode: String?
  /// Whether the resolved observation needs a foreground update.
  public let localIsStale: Bool

  /// Resolves a canonical selection for the supplied permission and observation time.
  public init(
    codes: [String], location: WidgetLocation?, status: WidgetLocationStatus, now: Date = .now
  ) {
    canonical = WidgetSelection.normalize(codes, allowsLocal: true)
    if canonical.contains(WidgetSelection.localID), status.allowsCache,
      let location, location.isUsable
    {
      localCode = location.currency
      localIsStale = !location.isFresh(now: now) || status == .failed
    } else {
      localCode = nil
      localIsStale = false
    }
    let detected = localCode
    self.codes = WidgetSelection.normalize(
      canonical.map {
        $0 == WidgetSelection.localID
          ? (detected.map { "@local:" + $0 } ?? WidgetSelection.localID) : $0
      }, allowsLocal: true)
  }
}

/// Persisted permission/lookup outcome, separate from the last supported observation.
public enum WidgetLocationStatus: String, Codable, Sendable {
  case notDetermined, denied, restricted, available, failed, removed

  /// Whether the outcome permits displaying the last supported observation.
  public var allowsCache: Bool { self == .available || self == .failed }
}

extension CurrencyStore {
  /// Loads saved permission status, inferring legacy observation availability.
  public func widgetLocationStatus() -> WidgetLocationStatus {
    guard
      let data = try? Data(
        contentsOf: directory.appendingPathComponent("widget-location-status.json")),
      let status = try? JSONDecoder().decode(WidgetLocationStatus.self, from: data)
    else { return widgetLocation() == nil ? .notDetermined : .available }
    return status
  }

  /// Atomically persists the latest permission or lookup outcome.
  public func saveWidgetLocationStatus(_ status: WidgetLocationStatus) throws {
    try coordinate("widget-location-status.json") {
      try JSONEncoder().encode(status)
        .write(
          to: directory.appendingPathComponent("widget-location-status.json"), options: .atomic)
    }
  }
}
