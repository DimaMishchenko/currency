import Foundation

/// A source of normalized currency quotes.
public protocol RateProvider: Sendable {
  /// Returns positive, EUR-normalized quotes keyed by uppercase currency code.
  /// Implementations must propagate task cancellation and retain provider provenance.
  func fetch() async throws -> [String: ExchangeRate]
}
