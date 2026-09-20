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
  ///   - providerTimeout: Optional per-provider deadline for latency-sensitive widget timelines.
  /// - Returns: A usable snapshot with an optional recoverable warning.
  public func refresh(
    previous: RateSnapshot, force: Bool = false, now: Date = .now,
    providerTimeout: Duration? = nil
  ) async -> RefreshResult {
    guard !Task.isCancelled else { return RefreshResult(snapshot: previous, warning: nil) }
    let refreshDaily =
      force || previous.dailyQuotes == nil
      || now < (previous.dailyFetchedAt ?? .distantPast)
      || now.timeIntervalSince(previous.dailyFetchedAt ?? .distantPast) >= 21600
    async let fiatResult = refreshDaily ? fetch(fiat, timeout: providerTimeout) : nil
    async let dailyResult = refreshDaily ? fetch(daily, timeout: providerTimeout) : nil
    async let cryptoResult = fetch(crypto, timeout: providerTimeout)
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

  /// Starts all providers concurrently and yields after each completion. Consuming hosts
  /// own the foreground deadline, so an uncooperative provider cannot keep recovery pending.
  /// The stream preserves daily fallbacks and the primary provider's equal-date precedence.
  public func bootstrap(previous: RateSnapshot, now: Date = .now) -> AsyncStream<BootstrapUpdate> {
    let providers: [(Int, any RateProvider)] =
      [(0, daily), (1, fiat)]
      + (crypto.map { [(2, $0)] } ?? [])
    return AsyncStream { continuation in
      let worker = Task {
        await withTaskGroup(of: BootstrapProviderResult.self) { group in
          for (index, provider) in providers {
            group.addTask {
              do {
                let quotes = try await provider.fetch()
                try Task.checkCancellation()
                let valid = quotes.filter {
                  CurrencyCatalog.codes.contains($0.key) && !$0.value.value.isNaN
                    && $0.value.value > 0
                }
                return BootstrapProviderResult(index: index, quotes: valid, failure: nil)
              } catch {
                let offline =
                  (error as? URLError)
                  .map {
                    $0.code == .notConnectedToInternet || $0.code == .networkConnectionLost
                  } ?? false
                return BootstrapProviderResult(
                  index: index, quotes: nil, failure: offline ? .offline : .unavailable)
              }
            }
          }
          var results: [Int: BootstrapProviderResult] = [:]
          for await result in group {
            guard !Task.isCancelled else { break }
            results[result.index] = result
            var dailyQuotes =
              previous.dailyQuotes
              ?? previous.quotes.filter { $0.value.overlayTimestamp == nil }
            // Rebuild from fixed provider order, never completion order.
            for index in [0, 1] {
              for (code, quote) in results[index]?.quotes ?? [:]
              where quote.published >= (dailyQuotes[code]?.published ?? "") {
                dailyQuotes[code] = quote
              }
            }
            var effective = dailyQuotes
            var liveQuotes = results[2]?.quotes ?? [:]
            // A pending provider has not invalidated the cached overlay. Keep it until
            // crypto actually returns, then use only that result or the daily fallback.
            if crypto != nil, results[2] == nil, previous.hasValidFetchTimestamp(now: now) {
              liveQuotes = previous.quotes.filter {
                $0.value.overlayTimestamp != nil && !$0.value.value.isNaN && $0.value.value > 0
              }
            }
            for (code, quote) in liveQuotes
            where CurrencyCatalog.crypto.contains(code)
              && quote.published >= (dailyQuotes[code]?.published ?? "")
            {
              effective[code] = quote
            }
            let succeeded = results.values.contains { !($0.quotes ?? [:]).isEmpty }
            let final = results.count == providers.count
            // "Offline" is justified only if every provider actually reports connectivity loss.
            let failure: BootstrapFailure? =
              final && !succeeded
              ? (results.values.allSatisfy { $0.failure == .offline } ? .offline : .unavailable)
              : nil
            continuation.yield(
              BootstrapUpdate(
                snapshot: RateSnapshot(
                  quotes: effective, fetchedAt: succeeded ? now : previous.fetchedAt,
                  dailyQuotes: dailyQuotes,
                  dailyFetchedAt: results[0]?.quotes != nil && results[1]?.quotes != nil
                    ? now : previous.dailyFetchedAt,
                  checkedAt: now),
                isFinal: final, failure: failure))
          }
          group.cancelAll()
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in worker.cancel() }
    }
  }

  private func fetch(
    _ provider: (any RateProvider)?, timeout: Duration?
  ) async -> [String: ExchangeRate]? {
    guard let provider else { return nil }
    guard let timeout else { return try? await provider.fetch() }
    return await withTaskGroup(of: [String: ExchangeRate]?.self) { group in
      group.addTask { try? await provider.fetch() }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return nil
      }
      let quotes = await group.next() ?? nil
      group.cancelAll()
      return quotes
    }
  }
}

private struct BootstrapProviderResult: Sendable {
  let index: Int
  let quotes: [String: ExchangeRate]?
  let failure: BootstrapFailure?
}
