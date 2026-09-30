import ExchangeRates
import Foundation

/// One destination's unrounded value and the exact quote legs used to calculate it.
public struct ConversionResult: Sendable, Identifiable {
  /// Availability of one destination independently of other requested results.
  public enum Availability: String, Sendable {
    /// A value, unresolved Local, missing quote metadata or unrepresentable calculation.
    case available, localUnavailable, missingRates, overflow
  }
  /// Invocation-time destination identity and Local observation.
  public let destination: ConversionDestination
  /// Unrounded output text, absent for unavailable results.
  public let amount: String?
  /// Typed result availability; unavailable values are never encoded as zero.
  public let availability: Availability
  /// Source quote actually used, absent for identity calculations.
  public let sourceQuote: ExchangeRate?
  /// Destination quote actually used, absent for identity calculations.
  public let targetQuote: ExchangeRate?
  /// Whether a refresh failure affected this calculation's quote legs.
  public let refreshFailed: Bool
  /// Whether this calculation uses daily cryptocurrency fallback data.
  public let dailyFallback: Bool
  /// Whether the relevant quote or daily-cache timestamps are outside their reuse window.
  public let cacheIsStale: Bool
  /// Selection identity preserves fixed and Local rows with identical resolved codes.
  public var id: String { destination.id }
}

/// Immutable invocation output, shared by speech, Shortcuts and read-only presentation.
public struct ConversionEvaluation: Sendable {
  /// Immutable validated request associated with this evaluation.
  public let request: ConversionRequest
  /// Ordered successes and unavailable destinations.
  public let results: [ConversionResult]
  /// Time the returned snapshot was evaluated.
  public let evaluatedAt: Date
  /// Retrieval metadata for a snapshot used by successful nonidentity calculations.
  public let fetchedAt: Date?
  /// Whether a relevant refresh or persistence operation failed.
  public let refreshFailed: Bool
  /// Whether successful crypto calculations used a daily fallback quote.
  public let dailyFallback: Bool
  /// Whether the used snapshot is outside the normal attempt window.
  public let cacheIsStale: Bool

  /// Pure evaluation, including partial failures and rate-independent same-code calculations.
  public init(
    request: ConversionRequest, snapshot: RateSnapshot, now: Date, refreshFailed: Bool = false,
    warning: RefreshWarning? = nil
  ) throws {
    self.request = try request.validated()
    guard let input = ExactAmount.parse(request.amount) else { throw ConversionError.invalidAmount }
    evaluatedAt = now
    results = request.destinations.map { destination in
      let sourceQuote = snapshot.quotes[request.source]
      let targetQuote = destination.code.flatMap { snapshot.quotes[$0] }
      func result(
        _ availability: ConversionResult.Availability, _ amount: Decimal? = nil
      ) -> ConversionResult {
        let usesQuotes = availability == .available && destination.code != request.source
        let legs = usesQuotes ? [sourceQuote, targetQuote].compactMap { $0 } : []
        let dailyFallback =
          usesQuotes
          && [(request.source, sourceQuote), (destination.code ?? "", targetQuote)]
            .contains { code, quote in
              CurrencyCatalog.crypto.contains(code) && quote != nil
                && quote?.isLive == false
            }
        let failed: Bool
        switch warning {
        case .dailyRatesUnavailable:
          failed =
            usesQuotes && (refreshFailed || legs.contains { !$0.isLive })
        case .partialCryptoFallback: failed = usesQuotes && (refreshFailed || dailyFallback)
        case nil: failed = usesQuotes && refreshFailed
        }
        let stale = legs.contains { quote in
          let overlay = quote.observedAt ?? quote.retrievedAt
          let dailyTimestamp =
            quote.source.provider == .fawaz
            ? snapshot.supplementalFetchedAt : snapshot.fiatFetchedAt
          let timestamp =
            overlay ?? quote.cachedAt ?? dailyTimestamp ?? snapshot.dailyFetchedAt
            ?? snapshot.fetchedAt
          let window: TimeInterval =
            overlay == nil
              && (quote.cachedAt != nil || dailyTimestamp != nil || snapshot.dailyFetchedAt != nil)
            ? 21600 : 1800
          return !timestamp.timeIntervalSince1970.isFinite || timestamp > now
            || now.timeIntervalSince(timestamp) >= window
        }
        return ConversionResult(
          destination: destination, amount: amount.map(ExactAmount.string),
          availability: availability,
          sourceQuote: usesQuotes ? sourceQuote : nil,
          targetQuote: usesQuotes ? targetQuote : nil,
          refreshFailed: failed, dailyFallback: dailyFallback, cacheIsStale: stale)
      }
      guard let code = destination.code else { return result(.localUnavailable) }
      if code == request.source { return result(.available, input) }
      guard snapshot.hasValidFetchTimestamp(now: now),
        let a = sourceQuote?.value, let b = targetQuote?.value,
        !a.isNaN, !b.isNaN, a > 0, b > 0
      else { return result(.missingRates) }
      guard let converted = snapshot.convert(input, from: request.source, to: code),
        input == 0 || converted > 0
      else { return result(.overflow) }
      return result(.available, converted)
    }
    let used = results.filter {
      $0.availability == .available && $0.destination.code != request.source
    }
    fetchedAt = used.isEmpty ? nil : snapshot.fetchedAt
    cacheIsStale = results.contains(where: \.cacheIsStale)
    dailyFallback = results.contains(where: \.dailyFallback)
    self.refreshFailed = results.contains(where: \.refreshFailed)
  }
}
