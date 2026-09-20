import Conversion
import ExchangeRates
import Foundation
import LocalCurrency

/// Recoverable Home operations, localized by HomeUI.
public enum HomeIssue: Sendable, Equatable {
  case selectionSaveFailed, rateSaveFailed
  case rateWarning(RefreshWarning)
}

/// The outcome of one manual refresh, independent of its localized presentation.
public enum HomeRefreshOutcome: Sendable, Equatable {
  case refreshed, warning, failed, cancelled, ignored
}

/// Currency identity and current rates passed to application-owned details presentation.
public struct HomeDetailsRequest: Sendable {
  /// Stable row identity, including a distinct dynamic Local selection.
  public let selectionID: String
  /// Resolved currency to inspect.
  public let code: String
  /// The workspace base used as the preferred reference.
  public let reference: String
  /// The displayed rate snapshot at selection time.
  public let snapshot: RateSnapshot
  /// Creates a details request without naming an application route.
  public init(selectionID: String, code: String, reference: String, snapshot: RateSnapshot) {
    self.selectionID = selectionID; self.code = code
    self.reference = reference; self.snapshot = snapshot
  }
}

/// Semantic requests interpreted by the scene coordinator.
public enum HomeOutput: Sendable {
  case detailsRequested(HomeDetailsRequest)
  case settingsRequested, widgetsRequested, locationRequested
}

/// Focused capabilities captured once by each Home flow.
@MainActor
public struct HomeDependencies {
  /// Reads confirmed shared input.
  public var readInput: () -> ConverterState
  /// Reads committed rates.
  public var readRates: () -> RateSnapshot
  /// Reads the latest shared refresh result, including foreground refresh storage failures.
  public var readRateIssue: () -> HomeIssue?
  /// Reads the current coarse observation and authorization status.
  public var readLocalCurrency: () -> (WidgetLocation?, WidgetLocationStatus)
  /// Mutates freshly loaded input under the storage owner's coordination.
  public var editInput: ((inout ConverterState) throws -> Void) throws -> ConverterState
  /// Performs a requested refresh and returns committed results.
  public var refreshRates: (Bool) async throws -> RefreshResult
  /// Observes authoritative input, rate and location changes for this flow.
  public var changes: () -> AsyncStream<Void>

  /// Creates required operations without hidden global services.
  public init(
    readInput: @escaping () -> ConverterState, readRates: @escaping () -> RateSnapshot,
    readRateIssue: @escaping () -> HomeIssue?,
    readLocalCurrency: @escaping () -> (WidgetLocation?, WidgetLocationStatus),
    editInput: @escaping ((inout ConverterState) throws -> Void) throws -> ConverterState,
    refreshRates: @escaping (Bool) async throws -> RefreshResult,
    changes: @escaping () -> AsyncStream<Void>
  ) {
    self.readInput = readInput; self.readRates = readRates
    self.readRateIssue = readRateIssue
    self.readLocalCurrency = readLocalCurrency; self.editInput = editInput
    self.refreshRates = refreshRates; self.changes = changes
  }
}
