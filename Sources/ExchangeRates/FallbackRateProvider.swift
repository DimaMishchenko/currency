import Foundation

/// A fiat provider with a primary source and fallback.
public struct FallbackRateProvider: RateProvider {
  let primary: any RateProvider
  let fallback: any RateProvider
  /// Creates a chained fiat provider.
  public init(
    primary: any RateProvider = FrankfurterProvider(), fallback: any RateProvider = ECBProvider()
  ) {
    self.primary = primary
    self.fallback = fallback
  }

  /// Fetches from the primary provider or its fallback.
  public func fetch() async throws -> [String: ExchangeRate] {
    do { return try await primary.fetch() } catch {
      try Task.checkCancellation()
      return try await fallback.fetch()
    }
  }
}
