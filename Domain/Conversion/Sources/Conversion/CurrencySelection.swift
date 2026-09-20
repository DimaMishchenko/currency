import ExchangeRates
import Foundation
import LocalCurrency

/// Ordered canonical lists are independent of the number of visible widget slots.
public enum CurrencySelection {
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

  /// App selection with Local intent preserved for synchronized widgets.
  public static func appConfiguration(_ input: ConverterState) -> [String] {
    normalize(
      [input.source] + input.manualDestinations + (input.usesLocalCurrency ? [localID] : []),
      allowsLocal: true)
  }

}

/// Resolves a local slot without replacing a failed lookup with an arbitrary currency.
public struct ResolvedCurrencySelection: Equatable, Sendable {
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
    canonical = CurrencySelection.normalize(codes, allowsLocal: true)
    if canonical.contains(CurrencySelection.localID), status.allowsCache,
      let location, location.isUsable
    {
      localCode = location.currency
      localIsStale = !location.isFresh(now: now) || status == .failed
    } else {
      localCode = nil
      localIsStale = false
    }
    let detected = localCode
    self.codes = CurrencySelection.normalize(
      canonical.map {
        $0 == CurrencySelection.localID
          ? (detected.map { "@local:" + $0 } ?? CurrencySelection.localID) : $0
      }, allowsLocal: true)
  }
}
