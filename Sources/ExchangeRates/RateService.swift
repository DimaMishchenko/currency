import Foundation

/// The result of refreshing rates.
public struct RefreshResult: Sendable {
  /// The resulting rate snapshot.
  public let snapshot: RateSnapshot
  /// A recoverable condition when part of the refresh failed.
  public let warning: RefreshWarning?
  /// Creates a refresh outcome, including any recoverable provider condition.
  public init(snapshot: RateSnapshot, warning: RefreshWarning?) {
    self.snapshot = snapshot
    self.warning = warning
  }
}

/// Coordinates rate providers and preserves usable cached quotes.
public actor RateService {
  private let fiat: any RateProvider
  private let daily: any RateProvider

  private let crypto: (any RateProvider)?
  /// Creates a rate service from its providers.
  public init(
    fiat: any RateProvider = FallbackRateProvider(), daily: any RateProvider = FawazProvider(),
    crypto: (any RateProvider)? = CoinbaseProvider()
  ) {
    self.fiat = fiat
    self.daily = daily
    self.crypto = crypto
  }

  /// Refreshes providers and merges their EUR-normalized quotes with saved daily fallbacks.
  ///
  /// Newer publication dates win; primary fiat wins equal-date ties. Intraday crypto overlays
  /// are rebuilt on each call, so missing live quotes revert to daily data. Daily feeds are
  /// reused for six hours only after both daily providers succeed. Hosts control polling.
  /// - Parameters:
  ///   - previous: Last saved snapshot, including separate daily fallbacks when available.
  ///   - force: Bypasses the daily-feed freshness check.
  ///   - now: Evaluation time for freshness and returned timestamps.
  /// - Returns: A usable snapshot with an optional recoverable warning.
  public func refresh(
    previous: RateSnapshot, force: Bool = false, now: Date = .now
  ) async -> RefreshResult {
    guard !Task.isCancelled else { return RefreshResult(snapshot: previous, warning: nil) }
    let refreshDaily =
      force || previous.dailyQuotes == nil
      || now < (previous.dailyFetchedAt ?? .distantPast)
      || now.timeIntervalSince(previous.dailyFetchedAt ?? .distantPast) >= 21600
    async let fiatResult = refreshDaily ? fetch(fiat) : nil
    async let dailyResult = refreshDaily ? fetch(daily) : nil
    async let cryptoResult = fetch(crypto)
    let (fiatQuotes, supplementalQuotes) = await (fiatResult, dailyResult)
    var quotes = previous.dailyQuotes ?? previous.quotes.filter { $0.value.overlayTimestamp == nil }
    // Each quote retains its own publication date; never replace newer cache data with older data.
    for incoming in [supplementalQuotes, fiatQuotes] {
      for (code, quote) in incoming ?? [:]
      where quote.published >= (quotes[code]?.published ?? "") {
        quotes[code] = quote
      }
    }
    let dailyQuotes = quotes
    let live = await cryptoResult
    guard !Task.isCancelled else { return RefreshResult(snapshot: previous, warning: nil) }
    for (code, quote) in live ?? [:] where CurrencyCatalog.crypto.contains(code) {
      quotes[code] = quote
    }
    // Never leave an old intraday quote masquerading as current after Coinbase fails.
    let success = fiatQuotes != nil || supplementalQuotes != nil || live != nil
    let warning: RefreshWarning? =
      refreshDaily && fiatQuotes == nil && supplementalQuotes == nil
      ? .dailyRatesUnavailable
      : crypto != nil && !CurrencyCatalog.crypto.isSubset(of: Set(live?.keys.map { $0 } ?? []))
        ? .partialCryptoFallback : nil
    return RefreshResult(
      snapshot: RateSnapshot(
        quotes: quotes, fetchedAt: success ? now : previous.fetchedAt, dailyQuotes: dailyQuotes,
        dailyFetchedAt: fiatQuotes != nil && supplementalQuotes != nil
          ? now : previous.dailyFetchedAt,
        checkedAt: now), warning: warning)
  }

  private func fetch(_ provider: (any RateProvider)?) async -> [String: ExchangeRate]? {
    guard let provider else { return nil }
    return try? await provider.fetch()
  }
}
