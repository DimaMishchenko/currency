import CoordinatedFiles
import Foundation

/// Loads daily fiat references, dated fallback publications, bundled months, and intraday crypto.
public actor HistoryService {
  private let client: any HTTPClient
  private let directory: URL

  /// Whether a distinct catalog pair contains a cryptocurrency and no precious metal.
  public static func supportsIntraday(base: String, quote: String) -> Bool {
    base != quote && CurrencyCatalog.codes.contains(base) && CurrencyCatalog.codes.contains(quote)
      && (CurrencyCatalog.crypto.contains(base) || CurrencyCatalog.crypto.contains(quote))
      && !CurrencyCatalog.metals.contains(base) && !CurrencyCatalog.metals.contains(quote)
  }

  /// Whether providers can supply intraday references for this pair.
  public nonisolated func supportsIntraday(base: String, quote: String) -> Bool {
    Self.supportsIntraday(base: base, quote: quote)
  }

  /// Creates a history service using daily publications and intraday crypto references.
  public init(directory: URL, client: any HTTPClient = NetworkClient(timeout: 30)) {
    self.directory = directory
    self.client = client
  }

  /// Loads provider observations or returns compatible saved observations with an explicit stale issue.
  public func load(
    base: String, quote: String, range: HistoryRange, now: Date = .now,
    cacheLifetime: TimeInterval? = nil
  ) async -> HistoryResult {
    guard CurrencyCatalog.codes.contains(base), CurrencyCatalog.codes.contains(quote), base != quote
    else { return HistoryResult(series: nil, issue: .unsupportedPair) }
    guard range != .day || supportsIntraday(base: base, quote: quote) else {
      return HistoryResult(series: nil, issue: .intradayUnavailable)
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let year = calendar.component(.year, from: now)
    let interval = range == .yearToDate ? "\(range.rawValue)-\(year)" : "\(range.rawValue)"
    let file = directory.appendingPathComponent(
      "history-v3-\(base)-\(quote)-\(interval).json")
    let cachedData = try? Data(contentsOf: file)
    let record =
      cachedData
      .flatMap { try? JSONDecoder().decode(HistoryCacheRecord.self, from: $0) }
    let cached: HistorySeries? = record.flatMap { record in
      Self.validHistory(record.series, base: base, quote: quote, range: range, now: now)
        ? record.series : nil
    }
    let fiatPolicy =
      range != .day && range != .all && Self.usesFiatHistory(base: base, quote: quote)
    let lifetime: TimeInterval = range == .day ? 1800 : (range == .all ? 86400 : 21600)
    let fresh =
      cached.map { now.timeIntervalSince($0.fetchedAt) < (cacheLifetime ?? lifetime) } ?? false
    if let cached, fresh,
      !fiatPolicy || cached.source.provider != .fawaz || record?.fiatHistoryPolicyVersion == 1,
      range != .day || now < Self.nextHour(after: cached.fetchedAt)
    {
      return HistoryResult(series: cached, issue: nil)
    }
    do {
      let points: [HistoryPoint]
      let source: RateSource
      if range == .day {
        (points, source) = try await intraday(base: base, quote: quote, now: now)
      } else {
        let start: Date
        if range == .all {
          guard let date = calendar.date(from: DateComponents(year: 2024, month: 3, day: 2))
          else { throw RateError.invalidData }
          start = date
        } else {
          guard let date = Self.historyStart(range: range, at: now, calendar: calendar)
          else { throw RateError.invalidData }
          start = date
        }
        let older =
          range == .all ? try BundledHistory.points(base: base, quote: quote, through: now) : []
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start
        else { throw RateError.invalidData }
        let bundledRecent =
          range == .all
          ? BundledHistory.recentPoints(
            base: base, quote: quote,
            through: monthStart.addingTimeInterval(-1)) : []
        let recent: [HistoryPoint]
        var dailyProvider: RateProviderID = .fawaz
        if range == .all {
          let lastBundled = bundledRecent.last?.date ?? start.addingTimeInterval(-86400)
          guard let missingStart = calendar.date(byAdding: .month, value: 1, to: lastBundled)
          else { throw RateError.invalidData }
          let latest: [HistoryPoint]?
          if missingStart >= monthStart {
            latest = []
          } else {
            latest = try? await Self.fetchDailyHistory(
              client: client, directory: directory, base: base, quote: quote,
              start: max(missingStart, start), now: monthStart.addingTimeInterval(-86400),
              monthly: true)
          }
          try Task.checkCancellation()
          if latest == nil && cached == nil && older.count + bundledRecent.count < 2 {
            throw RateError.unavailable
          }
          recent = bundledRecent + (latest ?? [])
          if latest == nil {
            let fallback =
              cached
              ?? HistorySeries(
                points: older + bundledRecent,
                source: Self.monthlySource(
                  base: base, quote: quote, hasOlder: !older.isEmpty,
                  hasRecent: !bundledRecent.isEmpty),
                fetchedAt: bundledRecent.last?.date ?? older.last?.date ?? now)
            return HistoryResult(series: fallback, issue: .usingCachedSeries)
          }
        } else if Self.usesFiatHistory(base: base, quote: quote) {
          do {
            recent = try await Self.fetchFiatHistory(
              client: client, base: base, quote: quote, start: start, now: now)
            dailyProvider = .frankfurter
          } catch {
            try Task.checkCancellation()
            if cached?.source.provider == .frankfurter { throw error }
            if let cached, let cachedData, fresh, record?.fiatHistoryPolicyVersion != 1 {
              do {
                let latest = try Self.recordFailedFiatRefresh(
                  at: file, originalData: cachedData, cached: cached,
                  base: base, quote: quote, range: range, now: now)
                return HistoryResult(series: latest, issue: .usingCachedSeries)
              } catch {
                return HistoryResult(series: cached, issue: .cacheWriteFailed)
              }
            }
            recent = try await Self.fetchDailyHistory(
              client: client, directory: directory, base: base, quote: quote,
              start: start, now: now, monthly: false)
          }
        } else {
          recent = try await Self.fetchDailyHistory(
            client: client, directory: directory, base: base, quote: quote,
            start: start, now: now, monthly: false)
        }
        points = older + recent
        source =
          range == .all
          ? Self.monthlySource(
            base: base, quote: quote, hasOlder: !older.isEmpty, hasRecent: !recent.isEmpty)
          : RateSource(provider: dailyProvider, observation: .dailyReference, timeZone: .gmt)

      }
      try Task.checkCancellation()
      let series = HistorySeries(points: points, source: source, fetchedAt: now)
      guard Self.validHistory(series, base: base, quote: quote, range: range, now: now)
      else { throw RateError.invalidData }
      do {
        try FileCoordination.write(at: file) {
          try JSONEncoder()
            .encode(
              HistoryCacheRecord(series: series, fiatHistoryPolicyVersion: fiatPolicy ? 1 : nil)
            )
            .write(to: file, options: .atomic)
        }
      } catch {
        return HistoryResult(series: series, issue: .cacheWriteFailed)
      }
      return HistoryResult(series: series, issue: nil)
    } catch {
      return HistoryResult(series: cached, issue: cached == nil ? .unavailable : .usingCachedSeries)
    }
  }

  private static func monthlySource(
    base: String, quote: String, hasOlder: Bool, hasRecent: Bool
  ) -> RateSource {
    var providers: [RateProviderID] = hasRecent ? [.fawaz] : []
    if hasOlder {
      if CurrencyCatalog.crypto.contains(base) || CurrencyCatalog.crypto.contains(quote) {
        providers.append(.coinMetrics)
      }
      if (!CurrencyCatalog.crypto.contains(base) && base != "USD")
        || (!CurrencyCatalog.crypto.contains(quote) && quote != "USD")
      {
        providers.append(.frankfurter)
      }
    }
    return RateSource(
      provider: providers.first ?? .fawaz, observation: .monthlyReference,
      timeZone: .gmt,
      contributingProviders: providers.count > 1 ? Array(providers.dropFirst()) : nil)
  }

  private func intraday(
    base: String, quote: String, now: Date
  ) async throws -> ([HistoryPoint], RateSource) {
    let end = Self.minuteEndpoint(now)
    let start = end.addingTimeInterval(-86400)
    let assets = [base, quote].filter { CurrencyCatalog.crypto.contains($0) }
    let observations = try await CoinMetricsClient(client: client, directory: directory)
      .observations(
        assets: assets, start: start, end: end, frequency: "1m")
    for asset in assets {
      guard let values = observations[asset], values.count >= 1380,
        Self.coversDay(values, ending: end)
      else {
        throw RateError.unavailable
      }
    }
    var conversion: RateConversion?
    let fiat = [base, quote].first { !CurrencyCatalog.crypto.contains($0) && $0 != "USD" }
    var fiatUSD = 1.0
    if let fiat {
      let day = String(end.ISO8601Format().prefix(10))
      let rates = try await Self.dailySnapshot(client: client, directory: directory, day: day)
      let canonical = ["GGP", "IMP", "JEP"].contains(fiat) ? "GBP" : fiat
      guard let usd = rates["USD"], let fx = rates[canonical] else { throw RateError.unavailable }
      let rate = fx.value / usd.value
      fiatUSD = NSDecimalNumber(decimal: 1 / rate).doubleValue
      conversion = RateConversion(
        provider: .fawaz, published: day, value: rate, base: "USD", quote: fiat)
    }
    let dates = observations[assets[0], default: []].map(\.date)
    let byAsset = observations.mapValues {
      Dictionary($0.map { ($0.date, $0.value) }, uniquingKeysWith: { _, last in last })
    }
    let points =
      dates.compactMap { date -> HistoryPoint? in
        guard Int(date.timeIntervalSince1970) % 300 == 0 else { return nil }
        let a = CurrencyCatalog.crypto.contains(base) ? byAsset[base]?[date] : fiatUSD
        let b = CurrencyCatalog.crypto.contains(quote) ? byAsset[quote]?[date] : fiatUSD
        guard let a, let b, a > 0, b > 0 else { return nil }
        return HistoryPoint(date: date, value: a / b)
      }
      .sorted { $0.date < $1.date }
    guard Self.coversDay(points, ending: end),
      points.allSatisfy({ $0.value.isFinite && $0.value > 0 })
    else {
      throw RateError.unavailable
    }
    return (
      points,
      RateSource(
        provider: .coinMetrics, observation: .minuteReference,
        timeZone: .gmt, conversion: conversion)
    )
  }

  private static func minuteEndpoint(_ date: Date) -> Date {
    Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60)
  }

  static func coversDay(_ points: [HistoryPoint], ending end: Date) -> Bool {
    guard let first = points.first, let last = points.last, points.count >= 270,
      first.date <= end.addingTimeInterval(-85500), last.date >= end.addingTimeInterval(-900),
      first.date >= end.addingTimeInterval(-86400), last.date <= end
    else { return false }
    return zip(points, points.dropFirst())
      .allSatisfy { a, b in
        b.date > a.date && b.date.timeIntervalSince(a.date) <= 900
      }
  }

  /// The next UTC hourly boundary, retained for widget scheduling compatibility.
  public static func nextHour(after date: Date) -> Date {
    Date(timeIntervalSince1970: (floor(date.timeIntervalSince1970 / 3600) + 1) * 3600)
  }
}
