import Foundation

extension HistoryResult {
  /// Ends a crypto chart at the same timestamped quote used by the converter.
  /// Historical samples after that observation are excluded rather than mixing quote times.
  public func includingLatestQuote(
    from snapshot: RateSnapshot, base: String, quote: String, now: Date = .now
  ) -> HistoryResult {
    guard HistoryService.supportsIntraday(base: base, quote: quote), let series,
      series.points.count >= 2,
      series.points.allSatisfy({ $0.value.isFinite && $0.value > 0 }),
      zip(series.points, series.points.dropFirst()).allSatisfy({ $0.date < $1.date })
    else { return self }
    guard let endpoint = snapshot.historyQuote(base: base, quote: quote, now: now)
    else { return HistoryResult(series: series, issue: .usingCachedSeries) }
    let legs = [base, quote].filter { CurrencyCatalog.crypto.contains($0) }
      .compactMap { snapshot.quotes[$0] }
    let points = series.points.filter { $0.date < endpoint.date } + [endpoint]
    guard points.count >= 2 else {
      return HistoryResult(series: nil, issue: .unavailable)
    }
    let current = legs[0].source
    var providers = [current.provider]
    for source in legs.map(\.source) + [series.source] {
      for provider in [source.provider] + (source.contributingProviders ?? [])
      where !providers.contains(provider) {
        providers.append(provider)
      }
    }
    let fiat = [base, quote].first { !CurrencyCatalog.crypto.contains($0) && $0 != "USD" }
    var fx: RateConversion?
    if let fiat, let fiatRate = snapshot.quotes[fiat],
      let rate = snapshot.convert(1, from: "USD", to: fiat), rate > 0
    {
      fx = RateConversion(
        provider: fiatRate.source.provider, published: fiatRate.published,
        value: rate, base: "USD", quote: fiat)
      if !providers.contains(fiatRate.source.provider) {
        providers.append(fiatRate.source.provider)
      }
    }
    let stale = legs.contains { !$0.isLive } || now.timeIntervalSince(endpoint.date) > 600
    return HistoryResult(
      series: HistorySeries(
        points: points,
        source: RateSource(
          provider: current.provider,
          observation: [.minuteReference, .hourlyReference].contains(series.source.observation)
            ? series.source.observation : .unspecified,
          timeZone: .gmt,
          conversion: fx,
          contributingProviders: providers.count > 1 ? Array(providers.dropFirst()) : nil),
        fetchedAt: max(series.fetchedAt, snapshot.fetchedAt)),
      issue: stale || issue == .usingCachedSeries ? .usingCachedSeries : issue)
  }
}

extension RateSnapshot {
  /// The timestamped shared conversion endpoint for a supported crypto history pair.
  /// Missing, invalid or future observations cannot supply a chart endpoint.
  public func historyQuote(base: String, quote: String, now: Date = .now) -> HistoryPoint? {
    guard HistoryService.supportsIntraday(base: base, quote: quote) else { return nil }
    let crypto = [base, quote].filter { CurrencyCatalog.crypto.contains($0) }
    let legs = crypto.compactMap { quotes[$0] }
    guard legs.count == crypto.count, let conversion = convert(1, from: base, to: quote)
    else { return nil }
    let value = NSDecimalNumber(decimal: conversion).doubleValue
    let dates = legs.compactMap { rate -> Date? in
      rate.observedAt ?? rate.retrievedAt
        ?? ISO8601DateFormatter().date(from: rate.published + "T00:00:00Z")
    }
    guard dates.count == legs.count, dates.allSatisfy({ $0 <= now }), let date = dates.min(),
      value.isFinite, value > 0
    else { return nil }
    return HistoryPoint(date: date, value: value)
  }
}
