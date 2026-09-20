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

  /// Creates the immutable context of a details flow.
  public init(code: String, reference: String, snapshot: RateSnapshot) {
    self.code = code
    self.reference = reference
    self.snapshot = snapshot
  }
}

/// The single capability required by history loading.
@MainActor
public struct CurrencyDetailsDependencies {
  /// Loads a series for (base currency, quote currency, range), preserving typed issues.
  public var loadHistory: (String, String, HistoryRange) async -> HistoryResult

  /// Creates explicit history loading without selecting a live provider.
  public init(loadHistory: @escaping (String, String, HistoryRange) async -> HistoryResult) {
    self.loadHistory = loadHistory
  }
}

/// Owns quote policy and cancellable history state independently of chart presentation.
@MainActor @Observable
public final class CurrencyDetailsModel {
  /// Mutually exclusive history request phases.
  public enum Phase: Sendable {
    case idle, loading, loaded
  }

  /// Immutable currency identity for this flow.
  public let input: CurrencyDetailsInput
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

  /// Constructs one model for a flow identity without starting work.
  public init(input: CurrencyDetailsInput, dependencies: CurrencyDetailsDependencies) {
    self.input = input
    self.dependencies = dependencies
  }

  /// Historical crypto quotes remain USD; invalid self/crypto references use a fiat alternative.
  public var quote: String {
    let currency = CurrencyCode(rawValue: input.code)
    let referenceCurrency = CurrencyCode(rawValue: input.reference)
    if currency?.isCryptocurrency == true { return CurrencyCode.usd.rawValue }
    if input.reference == input.code || referenceCurrency?.isCryptocurrency == true {
      return currency == .eur ? CurrencyCode.usd.rawValue : CurrencyCode.eur.rawValue
    }
    return input.reference
  }

  /// Replaces an older range request; cancellation and identity both guard publication.
  public func load() async {
    let identity = UUID()
    let requestedRange = range
    requestID = identity
    phase = .loading
    series = nil
    issue = nil
    let result = await dependencies.loadHistory(input.code, quote, requestedRange)
    guard !Task.isCancelled, requestID == identity, range == requestedRange else {
      if requestID == identity { phase = .idle }
      return
    }
    series = result.series
    issue = result.issue
    phase = .loaded
  }

  /// Invalidates the active flow even if a provider does not cooperate with cancellation.
  public func stop() {
    requestID = nil
    if phase == .loading { phase = .idle }
  }
}
