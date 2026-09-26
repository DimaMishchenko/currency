import ExchangeRates
import Foundation
import LocalCurrency

/// An explicit destination, retaining Local identity and its invocation-time observation.
public struct ConversionDestination: Equatable, Sendable, Identifiable {
  /// Fixed catalog code or the stable Local selection identifier.
  public let id: String
  /// Resolved catalog code, absent when Local was unavailable at invocation.
  public let code: String?
  /// Permitted observation associated with a resolved Local destination.
  public let localObservation: WidgetLocation?
  /// Whether that observation was stale or its latest lookup failed.
  public let localIsStale: Bool

  /// Creates a fixed destination, validated when constructing a request.
  public init(code: String) {
    id = code; self.code = code; localObservation = nil; localIsStale = false
  }

  /// Resolves Local once using the existing permission and observation policy.
  public init(local: WidgetLocation?, status: WidgetLocationStatus, now: Date) {
    let resolved = ResolvedCurrencySelection(
      codes: [CurrencySelection.localID], location: local, status: status, now: now)
    id = CurrencySelection.localID; code = resolved.localCode
    localObservation = resolved.localCode == nil ? nil : local
    localIsStale = resolved.localIsStale
  }

  /// Rejects destination values that could misrepresent a fixed or Local destination.
  public var isValid: Bool {
    if id == CurrencySelection.localID {
      return (code == nil && localObservation == nil && !localIsStale)
        || (code == localObservation?.currency && localObservation?.isUsable == true
          && localObservation?.updatedAt.timeIntervalSince1970.isFinite == true)
    }
    return id == code && CurrencyCatalog.codes.contains(id)
      && localObservation == nil && !localIsStale
  }
}

/// Read-only calculation input. Destinations are resolved once, not on every presentation.
public struct ConversionRequest: Equatable, Sendable {
  /// Canonical ungrouped amount text preserving Decimal precision.
  public let amount: String
  /// Supported fixed source currency code.
  public let source: String
  /// Ordered destinations including distinct fixed and Local identities.
  public let destinations: [ConversionDestination]

  /// Validates and normalizes an external calculation without mutating converter input.
  public init(amount: String, source: String, destinations: [ConversionDestination]) throws {
    guard let value = ExactAmount.parse(amount) else { throw ConversionError.invalidAmount }
    guard CurrencyCatalog.codes.contains(source) else { throw ConversionError.unsupportedCurrency }
    guard !destinations.isEmpty else { throw ConversionError.noDestinations }
    guard destinations.count <= CurrencyCatalog.codes.count + 1,
      destinations.allSatisfy(\.isValid), Set(destinations.map(\.id)).count == destinations.count
    else { throw ConversionError.unsupportedCurrency }
    self.amount = ExactAmount.string(value); self.source = source; self.destinations = destinations
  }

  /// Validates a external request using the same rules as intent parameters.
  public func validated() throws -> Self {
    try Self(amount: amount, source: source, destinations: destinations)
  }
}

/// Failures common to external conversion consumers.
public enum ConversionError: Error, Equatable, Sendable {
  /// Invalid inputs, unresolved destinations, unavailable quotes or unrepresentable arithmetic.
  case invalidAmount, unsupportedCurrency, noDestinations, localUnavailable, missingRates, overflow
}
