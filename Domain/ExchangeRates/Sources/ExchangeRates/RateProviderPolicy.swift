import Foundation

/// Provider capabilities selected by the host application.
public enum RateProviderPolicy: String, Sendable {
  /// Fawaz daily rates and daily historical observations for every supported asset.
  case daily
  /// Fawaz daily data with Coin Metrics current crypto reference rates and minute reference-rate charts.
  case intradayEnhanced

  /// Minimum spacing between background rate refresh attempts.
  public var refreshInterval: TimeInterval { self == .daily ? 21600 : 1800 }

  func filter(_ snapshot: RateSnapshot) -> RateSnapshot {
    let dictionaries = [
      snapshot.quotes, snapshot.dailyQuotes ?? [:], snapshot.fiatQuotes ?? [:],
      snapshot.supplementalQuotes ?? [:]
    ]
    let daily = dictionaries.reduce(into: [String: ExchangeRate]()) { result, quotes in
      result = RateSnapshot.mergeDaily(
        result,
        quotes.filter {
          $0.value.source.provider == .fawaz && !$0.value.isLive
        })
    }
    var effective = daily
    if self == .intradayEnhanced {
      for (code, quote) in snapshot.quotes
      where CurrencyCatalog.crypto.contains(code) && quote.source.provider == .coinMetrics
        && quote.isLive && quote.published >= (daily[code]?.published ?? "")
      {
        if let aligned = quote.alignedToDailyUSD(daily["USD"]) { effective[code] = aligned }
      }
    }
    let excluded = dictionaries.contains { quotes in
      quotes.contains { code, quote in
        quote.source.provider != .fawaz
          && !(self == .intradayEnhanced && CurrencyCatalog.crypto.contains(code)
            && quote.source.provider == .coinMetrics && quote.isLive)
      }
    }
    let dailyTime = daily.isEmpty ? nil : snapshot.supplementalFetchedAt ?? snapshot.dailyFetchedAt
    let allowedRetrieval =
      ([dailyTime] + effective.values.flatMap { [$0.cachedAt, $0.overlayTimestamp] })
      .compactMap { $0 }.max()
    let fetchedAt = excluded ? allowedRetrieval ?? .distantPast : snapshot.fetchedAt
    return RateSnapshot(
      quotes: effective, fetchedAt: effective.isEmpty ? .distantPast : fetchedAt,
      dailyQuotes: daily, dailyFetchedAt: dailyTime,
      checkedAt: excluded ? nil : snapshot.checkedAt,
      supplementalFetchedAt: dailyTime, fiatQuotes: [:], supplementalQuotes: daily)
  }
}
