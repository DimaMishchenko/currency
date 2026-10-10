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
  private let fiat: (any RateProvider)?
  private let daily: any RateProvider

  private let crypto: (any RateProvider)?
  private let policy: RateProviderPolicy?
  private let sleep: @Sendable (Duration) async throws -> Void
  /// Creates the provider set selected by the application, defaulting to daily Fawaz data.
  public init(policy: RateProviderPolicy = .daily, client: any HTTPClient = NetworkClient()) {
    self.policy = policy
    self.fiat = nil
    self.daily = FawazProvider(client: client)
    self.crypto = policy == .coinbaseEnhanced ? CoinbaseProvider(client: client) : nil
    self.sleep = { try await Task.sleep(for: $0) }
  }

  /// Creates a rate service from explicitly supplied providers.
  public init(
    fiat: any RateProvider, daily: any RateProvider = FawazProvider(),
    crypto: (any RateProvider)? = nil
  ) {
    self.policy = nil
    self.fiat = fiat
    self.daily = daily
    self.crypto = crypto
    self.sleep = { try await Task.sleep(for: $0) }
  }

  init(
    fiat: any RateProvider, daily: any RateProvider, crypto: (any RateProvider)?,
    sleep: @escaping @Sendable (Duration) async throws -> Void
  ) {
    self.policy = nil
    self.fiat = fiat
    self.daily = daily
    self.crypto = crypto
    self.sleep = sleep
  }

  /// Refreshes providers and merges their EUR-normalized quotes with saved daily fallbacks.
  ///
  /// Primary fiat quotes are preferred during their six-hour reuse window. Supplemental
  /// quotes fill missing assets and replace expired primary data after an unsuccessful retry.
  /// Providers retain independent success timestamps. Intraday crypto overlays are rebuilt
  /// on each call, so missing live quotes revert to daily data. Hosts control polling.
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
    let previous = policy?.filter(previous) ?? previous
    guard !Task.isCancelled else { return RefreshResult(snapshot: previous, warning: nil) }
    let refreshFiat =
      fiat != nil
      && (force
        || !RateSnapshot.isFresh(
          previous.fiatFetchedAt ?? (previous.fiatQuotes == nil ? previous.dailyFetchedAt : nil),
          now: now))
    let refreshSupplemental =
      force
      || !RateSnapshot.isFresh(
        previous.supplementalFetchedAt
          ?? (previous.supplementalQuotes == nil ? previous.dailyFetchedAt : nil), now: now)
    async let fiatResult = refreshFiat ? fetch(fiat, timeout: providerTimeout) : nil
    async let dailyResult = refreshSupplemental ? fetch(daily, timeout: providerTimeout) : nil
    async let cryptoResult = fetch(crypto, timeout: providerTimeout)
    let (fiatQuotes, supplementalQuotes) = await (fiatResult, dailyResult)
    let primary = RateSnapshot.mergeDaily(
      previous.primaryDailyQuotes,
      previous.recordingRetrieval(
        (fiatQuotes ?? [:]).filter { !CurrencyCatalog.crypto.contains($0.key) }, at: now),
      savedAt: fiatQuotes != nil
        ? previous.fiatFetchedAt ?? previous.dailyFetchedAt ?? previous.fetchedAt : nil)
    let supplemental = RateSnapshot.mergeDaily(
      previous.supplementalDailyQuotes,
      previous.recordingRetrieval(supplementalQuotes ?? [:], at: now),
      savedAt: supplementalQuotes != nil
        ? previous.supplementalFetchedAt ?? previous.dailyFetchedAt ?? previous.fetchedAt : nil)
    let fiatTime = fiatQuotes != nil ? now : previous.fiatFetchedAt ?? previous.dailyFetchedAt
    let supplementalTime =
      supplementalQuotes != nil ? now : previous.supplementalFetchedAt ?? previous.dailyFetchedAt
    let dailyQuotes = RateSnapshot.selectDaily(
      primary: primary, supplemental: supplemental,
      primaryFetchedAt: fiatTime, now: now)
    var quotes = dailyQuotes
    let live = await cryptoResult
    guard !Task.isCancelled else { return RefreshResult(snapshot: previous, warning: nil) }
    for (code, quote) in live ?? [:]
    where CurrencyCatalog.crypto.contains(code)
      && quote.published >= (dailyQuotes[code]?.published ?? "")
    {
      quotes[code] = quote
    }
    let success = fiatQuotes != nil || supplementalQuotes != nil || live != nil
    let warning: RefreshWarning? =
      (fiat == nil || refreshFiat && fiatQuotes == nil) && refreshSupplemental
        && supplementalQuotes == nil
      ? .dailyRatesUnavailable
      : crypto != nil && !CurrencyCatalog.crypto.isSubset(of: Set(live?.keys.map { $0 } ?? []))
        ? .partialCryptoFallback : nil
    return RefreshResult(
      snapshot: RateSnapshot(
        quotes: quotes, fetchedAt: success ? now : previous.fetchedAt, dailyQuotes: dailyQuotes,
        dailyFetchedAt: (fiat == nil || fiatQuotes != nil) && supplementalQuotes != nil
          ? now : previous.dailyFetchedAt,
        checkedAt: now, fiatFetchedAt: fiatTime, supplementalFetchedAt: supplementalTime,
        fiatQuotes: primary, supplementalQuotes: supplemental), warning: warning)
  }

  /// Starts all providers concurrently and yields after each completion. Consuming hosts
  /// own the foreground deadline, so an uncooperative provider cannot keep recovery pending.
  /// The stream preserves daily fallbacks and the primary provider's freshness precedence.
  public func bootstrap(previous: RateSnapshot, now: Date = .now) -> AsyncStream<BootstrapUpdate> {
    let previous = policy?.filter(previous) ?? previous
    let providers: [(Int, any RateProvider)] =
      [(0, daily)] + (fiat.map { [(1, $0)] } ?? [])
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
            let primary = RateSnapshot.mergeDaily(
              previous.primaryDailyQuotes,
              previous.recordingRetrieval(
                (results[1]?.quotes ?? [:]).filter { !CurrencyCatalog.crypto.contains($0.key) },
                at: now),
              savedAt: results[1]?.quotes != nil
                ? previous.fiatFetchedAt ?? previous.dailyFetchedAt ?? previous.fetchedAt : nil)
            let supplemental = RateSnapshot.mergeDaily(
              previous.supplementalDailyQuotes,
              previous.recordingRetrieval(results[0]?.quotes ?? [:], at: now),
              savedAt: results[0]?.quotes != nil
                ? previous.supplementalFetchedAt ?? previous.dailyFetchedAt ?? previous.fetchedAt
                : nil)
            let fiatTime =
              results[1]?.quotes != nil ? now : previous.fiatFetchedAt ?? previous.dailyFetchedAt
            let supplementalTime =
              results[0]?.quotes != nil
              ? now : previous.supplementalFetchedAt ?? previous.dailyFetchedAt
            let dailyQuotes = RateSnapshot.selectDaily(
              primary: primary, supplemental: supplemental,
              primaryFetchedAt: fiatTime, now: now)
            var effective = dailyQuotes
            var liveQuotes = results[2]?.quotes ?? [:]
            if crypto != nil, results[2] == nil, previous.hasValidFetchTimestamp(now: now) {
              liveQuotes = previous.quotes.filter {
                $0.value.isLive && !$0.value.value.isNaN && $0.value.value > 0
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
            let failure: BootstrapFailure? =
              final && !succeeded
              ? (results.values.allSatisfy { $0.failure == .offline } ? .offline : .unavailable)
              : nil
            continuation.yield(
              BootstrapUpdate(
                snapshot: RateSnapshot(
                  quotes: effective, fetchedAt: succeeded ? now : previous.fetchedAt,
                  dailyQuotes: dailyQuotes,
                  dailyFetchedAt: results[0]?.quotes != nil
                    && (fiat == nil || results[1]?.quotes != nil)
                    ? now : previous.dailyFetchedAt,
                  checkedAt: now, fiatFetchedAt: fiatTime, supplementalFetchedAt: supplementalTime,
                  fiatQuotes: primary, supplementalQuotes: supplemental),
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
    let sleep = self.sleep
    return await withTaskGroup(of: [String: ExchangeRate]?.self) { group in
      group.addTask { try? await provider.fetch() }
      group.addTask {
        try? await sleep(timeout)
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
