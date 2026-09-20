import Foundation

/// A provider-independent first-launch failure. Cancellation is deliberately not a failure.
public enum BootstrapFailure: Sendable, Equatable {
  case offline
  case unavailable
}

/// A progressively merged snapshot; hosts can continue as soon as their pair is usable.
public struct BootstrapUpdate: Sendable {
  /// Merged provider quotes and their retrieval metadata.
  public let snapshot: RateSnapshot
  /// Whether all providers have returned for this attempt.
  public let isFinal: Bool
  /// Aggregate failure, classified only once all providers finish.
  public let failure: BootstrapFailure?

  /// Creates a progressive provider result.
  public init(snapshot: RateSnapshot, isFinal: Bool, failure: BootstrapFailure? = nil) {
    self.snapshot = snapshot
    self.isFinal = isFinal
    self.failure = failure
  }
}

extension RateSnapshot {
  /// Rejects absent, nonfinite, and clearly future retrieval metadata while keeping old rates.
  public func hasValidFetchTimestamp(now: Date = .now) -> Bool {
    fetchedAt.timeIntervalSince1970.isFinite && fetchedAt > Date(timeIntervalSince1970: 0)
      && fetchedAt <= now.addingTimeInterval(300)
  }

  /// Checks a supported pair and its real retrieval timestamp, without an offline age limit.
  public func hasUsablePair(
    from base: String, to destination: String, amount: Decimal = 100, now: Date = .now
  ) -> Bool {
    guard base != destination, CurrencyCatalog.codes.contains(base),
      CurrencyCatalog.codes.contains(destination),
      hasValidFetchTimestamp(now: now),
      let a = quotes[base]?.value, let b = quotes[destination]?.value,
      !a.isNaN, !b.isNaN, a > 0, b > 0,
      let value = convert(amount, from: base, to: destination), !value.isNaN, value > 0
    else { return false }
    return true
  }
}
