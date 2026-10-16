import ExchangeRates
import Foundation
import Observation

/// The selected currency and reference used for one details flow.
public struct CurrencyDetailsInput: Sendable {
  /// Currency whose provenance and history are shown.
  public let code: String
  /// The originating workspace's base currency.
  public let reference: String
  /// The current rate snapshot supplied by the caller.
  public let snapshot: RateSnapshot
  /// Measurement used to present metal rates and history for this flow.
  public let metalUnit: MetalUnit

  /// Creates the immutable context of a details flow.
  public init(
    code: String, reference: String, snapshot: RateSnapshot,
    metalUnit: MetalUnit = .troyOunce
  ) {
    self.code = code
    self.reference = reference
    self.snapshot = snapshot
    self.metalUnit = metalUnit
  }
}

/// The single capability required by history loading.
@MainActor
public struct CurrencyDetailsDependencies {
  /// Loads a series for (base currency, quote currency, range), preserving typed issues.
  public var loadHistory: (String, String, HistoryRange) async -> HistoryResult

  /// Whether configured providers offer hourly history for the requested pair.
  public var supportsIntraday: (String, String) -> Bool

  /// Creates explicit history loading without selecting a live provider.
  public init(
    supportsIntraday: @escaping (String, String) -> Bool = {
      HistoryService.supportsIntraday(base: $0, quote: $1)
    },
    loadHistory: @escaping (String, String, HistoryRange) async -> HistoryResult
  ) {
    self.supportsIntraday = supportsIntraday
    self.loadHistory = loadHistory
  }
}

/// Owns quote policy and cancellable history state independently of chart presentation.
@MainActor @Observable
public final class CurrencyDetailsModel {
  /// Ranges offered by the details chart, ordered from short to long intervals.
  public nonisolated static let ranges: [HistoryRange] = [
    .day, .week, .month, .quarter, .yearToDate, .year, .all
  ]

  /// Fiat providers publish daily reference rates without intraday observations.
  public var availableRanges: [HistoryRange] {
    let request = historyRequest
    return Self.ranges.filter {
      $0 != .day || dependencies.supportsIntraday(request.base, request.quote)
    }
  }

  /// Mutually exclusive history request phases.
  public enum Phase: Sendable {
    case idle, loading, loaded
  }

  /// Immutable currency identity for this flow.
  public private(set) var input: CurrencyDetailsInput
  /// Selected historical range.
  public var range: HistoryRange = .month
  /// The current request phase.
  public private(set) var phase: Phase = .idle
  /// Latest accepted historical result.
  public private(set) var series: HistorySeries?
  /// Typed availability or persistence issue, localized by UI.
  public private(set) var issue: HistoryIssue?
  @ObservationIgnored private let dependencies: CurrencyDetailsDependencies
  @ObservationIgnored private var requestID: UUID?
  @ObservationIgnored private var loadedHistory: (range: HistoryRange, result: HistoryResult)?

  /// Constructs one model for a flow identity without starting work.
  public init(input: CurrencyDetailsInput, dependencies: CurrencyDetailsDependencies) {
    self.input = input
    self.dependencies = dependencies
  }

  /// Keeps the caller's comparison currency, with a distinct fallback for a self reference.
  public var quote: String {
    guard input.code == input.reference else { return input.reference }
    return input.code == CurrencyCode.eur.rawValue || CurrencyCatalog.crypto.contains(input.code)
      ? CurrencyCode.usd.rawValue : CurrencyCode.eur.rawValue
  }

  private var historyRequest: (base: String, quote: String, inverted: Bool) {
    if !CurrencyCatalog.crypto.contains(input.code), CurrencyCatalog.crypto.contains(quote) {
      return (quote, input.code, true)
    }
    return (input.code, quote, false)
  }

  /// Replaces an older range request; cancellation and identity both guard publication.
  public func load() async {
    let identity = UUID()
    let requestedRange = range
    requestID = identity
    phase = .loading
    series = nil
    issue = nil
    let request = historyRequest
    let result = await dependencies.loadHistory(request.base, request.quote, requestedRange)
    guard !Task.isCancelled, requestID == identity, range == requestedRange else {
      if requestID == identity { phase = .idle }
      return
    }
    loadedHistory = (requestedRange, result)
    apply(result)
    phase = .loaded
  }

  /// Updates quotes within the current details flow without replacing its selected history range.
  public func updateSnapshot(_ snapshot: RateSnapshot) {
    input = CurrencyDetailsInput(
      code: input.code, reference: input.reference,
      snapshot: snapshot, metalUnit: input.metalUnit)
    if phase == .loaded, let loadedHistory, loadedHistory.range == range {
      apply(loadedHistory.result)
    }
  }

  private func apply(_ history: HistoryResult) {
    let request = historyRequest
    let result = history.includingLatestQuote(
      from: input.snapshot, base: request.base, quote: request.quote)
    series = result.series.flatMap { received in
      let factor = NSDecimalNumber(decimal: input.metalUnit.rateFactor(from: input.code, to: quote))
        .doubleValue
      let points = received.points.map {
        HistoryPoint(date: $0.date, value: (request.inverted ? 1 / $0.value : $0.value) * factor)
      }
      guard points.allSatisfy({ $0.value.isFinite && $0.value > 0 }) else { return nil }
      return HistorySeries(points: points, source: received.source, fetchedAt: received.fetchedAt)

    }
    issue = result.series != nil && series == nil ? .unavailable : result.issue
  }

  /// Invalidates the active flow even if a provider does not cooperate with cancellation.
  public func stop() {
    requestID = nil
    if phase == .loading { phase = .idle }
  }
}
