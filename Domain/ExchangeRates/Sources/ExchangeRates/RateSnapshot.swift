import Foundation

/// A currency quote normalized against the euro.
public struct ExchangeRate: Codable, Sendable, Equatable {
  /// Currency units per one euro; must be positive and finite.
  public let value: Decimal
  /// The provider publication date, or retrieval day for untimestamped exchange rates.
  public let published: String
  /// Structured provider and observation metadata.
  public let source: RateSource
  /// The observation time for an intraday quote.
  public let observedAt: Date?
  /// Retrieval time when the provider supplies no market observation timestamp.
  public let retrievedAt: Date?
  /// Successful retrieval time of this cached daily quote, when known.
  public let cachedAt: Date?
  /// Creates a normalized quote.
  public init(
    _ value: Decimal, published: String, source: RateSource, observedAt: Date? = nil,
    retrievedAt: Date? = nil, cachedAt: Date? = nil
  ) {
    self.value = value
    self.published = published
    self.source = source

    self.observedAt = observedAt
    self.retrievedAt = retrievedAt
    self.cachedAt = cachedAt
  }

  /// Whether the quote represents a current intraday observation.
  public var isLive: Bool {
    observedAt != nil || retrievedAt != nil || source.observation == .trade
      || source.observation == .exchangeRate
  }

  var overlayTimestamp: Date? { observedAt ?? retrievedAt }
}

/// A persisted snapshot of current and daily currency quotes.
public struct RateSnapshot: Codable, Sendable {
  /// The effective quotes used for conversion.
  public let quotes: [String: ExchangeRate]
  /// The time at which effective quotes were fetched.
  public let fetchedAt: Date
  /// The most recent daily quotes before intraday overlays.
  public let dailyQuotes: [String: ExchangeRate]?
  /// The time at which daily quotes were fetched.
  public let dailyFetchedAt: Date?
  /// Last successful primary fiat retrieval, independently of supplemental availability.
  public let fiatFetchedAt: Date?
  /// Last successful supplemental retrieval, independently of primary fiat availability.
  public let supplementalFetchedAt: Date?
  /// Preserved primary quotes before supplemental selection.
  public let fiatQuotes: [String: ExchangeRate]?
  /// Preserved supplemental quotes, including offline cryptocurrency fallbacks.
  public let supplementalQuotes: [String: ExchangeRate]?
  /// The most recent refresh-attempt time.
  public let checkedAt: Date?
  /// Creates a rate snapshot.
  public init(
    quotes: [String: ExchangeRate] = [:], fetchedAt: Date = .distantPast,
    dailyQuotes: [String: ExchangeRate]? = nil, dailyFetchedAt: Date? = nil, checkedAt: Date? = nil,
    fiatFetchedAt: Date? = nil, supplementalFetchedAt: Date? = nil,
    fiatQuotes: [String: ExchangeRate]? = nil, supplementalQuotes: [String: ExchangeRate]? = nil
  ) {
    self.quotes = quotes
    self.fetchedAt = fetchedAt
    self.dailyQuotes = dailyQuotes

    self.dailyFetchedAt = dailyFetchedAt
    self.checkedAt = checkedAt
    self.fiatFetchedAt = fiatFetchedAt
    self.supplementalFetchedAt = supplementalFetchedAt
    self.fiatQuotes = fiatQuotes
    self.supplementalQuotes = supplementalQuotes
  }

  /// Converts an amount using the ratio of two EUR-normalized quotes.
  /// - Returns: The unrounded amount, or `nil` for missing/invalid rates or decimal overflow.
  ///   A same-currency conversion requires no quote. Rounding belongs to the consumer.
  public func convert(
    _ amount: Decimal, from: String, to: String, metalUnit: MetalUnit = .troyOunce
  ) -> Decimal? {
    guard !amount.isNaN else { return nil }
    if from == to { return amount }
    guard let a = quotes[from]?.value, let b = quotes[to]?.value, a > 0, b > 0 else { return nil }
    let sourceIsMetal = CurrencyCode(rawValue: from)?.isMetal == true
    let targetIsMetal = CurrencyCode(rawValue: to)?.isMetal == true
    let sourceAmount =
      sourceIsMetal && !targetIsMetal
      ? metalUnit.converted(amount, to: .troyOunce) : amount
    let quotedResult = sourceAmount / a * b
    let result =
      targetIsMetal && !sourceIsMetal
      ? MetalUnit.troyOunce.converted(quotedResult, to: metalUnit) : quotedResult
    return result.isNaN ? nil : result
  }
}

extension RateSnapshot {
  /// Merges concurrent refresh results without regressing published rates or trade times.
  ///
  /// The latest refresh attempt controls which live overlays remain available. An older
  /// result cannot resurrect a live quote removed by a newer failed refresh. Equal-date
  /// daily quotes prefer newer successful retrievals, then the latest attempt. The receiver
  /// wins when both retrieval and attempt timestamps are equal.
  public func merging(_ other: RateSnapshot) -> RateSnapshot {
    let latest = (checkedAt ?? fetchedAt) >= (other.checkedAt ?? other.fetchedAt) ? self : other
    let older = (checkedAt ?? fetchedAt) >= (other.checkedAt ?? other.fetchedAt) ? other : self
    let primary = Self.mergeDaily(older.primaryDailyQuotes, latest.primaryDailyQuotes)
    let supplement = Self.mergeDaily(older.supplementalDailyQuotes, latest.supplementalDailyQuotes)
    let primaryTime = [fiatFetchedAt, other.fiatFetchedAt].compactMap { $0 }.max()
    let supplementalTime = [supplementalFetchedAt, other.supplementalFetchedAt].compactMap { $0 }
      .max()
    let evaluation = latest.checkedAt ?? latest.fetchedAt
    let daily = Self.selectDaily(
      primary: primary, supplemental: supplement,
      primaryFetchedAt: primaryTime ?? latest.dailyFetchedAt, now: evaluation)
    var effective = daily
    for (code, quote) in latest.quotes where quote.isLive {
      var live = quote
      if let previous = older.quotes[code], let time = previous.overlayTimestamp,
        time > (live.overlayTimestamp ?? .distantPast)
      {
        live = previous
      }
      if live.published >= (daily[code]?.published ?? "") { effective[code] = live }
    }
    return RateSnapshot(
      quotes: effective, fetchedAt: max(fetchedAt, other.fetchedAt), dailyQuotes: daily,
      dailyFetchedAt: [dailyFetchedAt, other.dailyFetchedAt].compactMap { $0 }.max(),
      checkedAt: [checkedAt, other.checkedAt].compactMap { $0 }.max(),
      fiatFetchedAt: primaryTime, supplementalFetchedAt: supplementalTime,
      fiatQuotes: primary, supplementalQuotes: supplement)
  }

  func recordingRetrieval(
    _ incoming: [String: ExchangeRate], at now: Date
  ) -> [String: ExchangeRate] {
    incoming.mapValues { quote in
      ExchangeRate(
        quote.value, published: quote.published, source: quote.source,
        observedAt: quote.observedAt, retrievedAt: quote.retrievedAt, cachedAt: now)
    }
  }

  var primaryDailyQuotes: [String: ExchangeRate] {
    fiatQuotes
      ?? (dailyQuotes ?? quotes)
      .filter {
        !$0.value.isLive && $0.value.source.provider != .fawaz
          && !CurrencyCatalog.crypto.contains($0.key)
      }
  }

  var supplementalDailyQuotes: [String: ExchangeRate] {
    supplementalQuotes
      ?? (dailyQuotes ?? quotes)
      .filter {
        !$0.value.isLive
          && ($0.value.source.provider == .fawaz || CurrencyCatalog.crypto.contains($0.key))
      }
  }

  static func isFresh(_ timestamp: Date?, now: Date) -> Bool {
    guard let timestamp else { return false }
    return timestamp <= now && now.timeIntervalSince(timestamp) < 21600
  }

  static func mergeDaily(
    _ saved: [String: ExchangeRate], _ incoming: [String: ExchangeRate], savedAt: Date? = nil
  ) -> [String: ExchangeRate] {
    var merged = saved.mapValues { quote in
      guard quote.cachedAt == nil, let savedAt else { return quote }
      return ExchangeRate(
        quote.value, published: quote.published, source: quote.source,
        observedAt: quote.observedAt, retrievedAt: quote.retrievedAt, cachedAt: savedAt)
    }
    for (code, quote) in incoming {
      if let previous = merged[code],
        previous.published > quote.published
          || (previous.published == quote.published
            && (previous.cachedAt ?? savedAt ?? .distantPast) > (quote.cachedAt ?? .distantPast))
      {
        continue
      } else {
        merged[code] = quote
      }
    }
    return merged
  }

  static func selectDaily(
    primary: [String: ExchangeRate], supplemental: [String: ExchangeRate], primaryFetchedAt: Date?,
    now: Date
  ) -> [String: ExchangeRate] {
    var selected = primary
    for (code, quote) in supplemental
    where selected[code] == nil || CurrencyCatalog.crypto.contains(code)
      || (!isFresh(primary[code]?.cachedAt ?? primaryFetchedAt, now: now)
        && quote.published >= (selected[code]?.published ?? ""))
    {
      selected[code] = quote
    }
    return selected
  }

}
