import Conversion
import ExchangeRates
import Foundation
import LocalCurrency

/// Headless application operation; never constructs a feature or changes confirmed input.
public struct ConversionAction: Sendable {
  /// Consumer-owned operations with explicit shared-store and invocation lifetime.
  public struct Dependencies: Sendable {
    /// Reads the latest confirmed converter selection.
    public let readInput: @Sendable () -> ConverterState
    /// Reads observation and authorization together without requesting location.
    public let readLocal: @Sendable () -> (WidgetLocation?, WidgetLocationStatus)
    /// Reads the latest coordinated rate snapshot.
    public let readRates: @Sendable () -> RateSnapshot
    /// Performs a cancellable normal refresh through the domain store.
    public let refresh: @Sendable (Date) async throws -> RefreshResult
    /// Supplies evaluation and refresh-attempt time.
    public let now: @Sendable () -> Date
    /// Assembles explicit operations for an executable or isolated test.
    public init(
      readInput: @escaping @Sendable () -> ConverterState,
      readLocal: @escaping @Sendable () -> (WidgetLocation?, WidgetLocationStatus),
      readRates: @escaping @Sendable () -> RateSnapshot,
      refresh: @escaping @Sendable (Date) async throws -> RefreshResult,
      now: @escaping @Sendable () -> Date = { .now }
    ) {
      self.readInput = readInput; self.readLocal = readLocal; self.readRates = readRates
      self.refresh = refresh; self.now = now
    }
  }
  /// The explicitly supplied operations used by this action.
  public let dependencies: Dependencies
  /// Creates an action without selecting live stores implicitly.
  public init(dependencies: Dependencies) { self.dependencies = dependencies }

  /// Builds one immutable destination snapshot, preserving unresolved Local and row order.
  public func request(
    amount: String, source: String, destination: String? = nil
  ) throws -> ConversionRequest {
    let now = dependencies.now()
    let input = dependencies.readInput()
    let ids: [String]
    if let destination {
      ids = [destination]
    } else {
      ids = input.manualDestinations + (input.usesLocalCurrency ? [CurrencySelection.localID] : [])
    }
    let (location, status) =
      ids.contains(CurrencySelection.localID) ? dependencies.readLocal() : (nil, .notDetermined)
    let destinations = ids.map { id in
      id == CurrencySelection.localID
        ? ConversionDestination(local: location, status: status, now: now)
        : ConversionDestination(code: id)
    }
    return try ConversionRequest(
      amount: amount, source: source, destinations: destinations, metalUnit: input.metalUnit)
  }

  /// Refreshes only when due under the existing attempt throttle; cache errors remain disclosed.
  public func perform(_ request: ConversionRequest) async throws -> ConversionEvaluation {
    let request = try request.validated()
    try Task.checkCancellation()
    let now = dependencies.now()
    var snapshot = dependencies.readRates()
    var failed = false
    var warning: RefreshWarning?
    let needsRates = request.destinations.contains { $0.code != nil && $0.code != request.source }
    if needsRates,
      now < (snapshot.checkedAt ?? .distantPast)
        || now.timeIntervalSince(snapshot.checkedAt ?? .distantPast) >= 1800
    {
      do {
        let result = try await dependencies.refresh(now)
        snapshot = result.snapshot; warning = result.warning
      } catch is CancellationError { throw CancellationError() } catch {
        try Task.checkCancellation(); failed = true
      }
    }
    try Task.checkCancellation()
    return try ConversionEvaluation(
      request: request, snapshot: snapshot, now: dependencies.now(), refreshFailed: failed,
      warning: warning)
  }
}
