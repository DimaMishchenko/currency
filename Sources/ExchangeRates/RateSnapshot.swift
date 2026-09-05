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
  /// Creates a normalized quote.
  public init(
    _ value: Decimal, published: String, source: RateSource, observedAt: Date? = nil,
    retrievedAt: Date? = nil
  ) {
    self.value = value
    self.published = published
    self.source = source

    self.observedAt = observedAt
    self.retrievedAt = retrievedAt
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
  /// The most recent refresh-attempt time.
  public let checkedAt: Date?
  /// Creates a rate snapshot.
  public init(
    quotes: [String: ExchangeRate] = [:], fetchedAt: Date = .distantPast,
    dailyQuotes: [String: ExchangeRate]? = nil, dailyFetchedAt: Date? = nil, checkedAt: Date? = nil
  ) {
    self.quotes = quotes
    self.fetchedAt = fetchedAt
    self.dailyQuotes = dailyQuotes

    self.dailyFetchedAt = dailyFetchedAt
    self.checkedAt = checkedAt
  }

  /// Converts an amount using the ratio of two EUR-normalized quotes.
  /// - Returns: The unrounded amount, or `nil` for missing/invalid rates or decimal overflow.
  ///   A same-currency conversion requires no quote. Rounding belongs to the consumer.
  public func convert(_ amount: Decimal, from: String, to: String) -> Decimal? {
    guard !amount.isNaN else { return nil }
    if from == to { return amount }
    guard let a = quotes[from]?.value, let b = quotes[to]?.value, a > 0, b > 0 else { return nil }
    let result = amount / a * b
    return result.isNaN ? nil : result
  }
}

extension RateSnapshot {
  /// Merges concurrent refresh results without regressing published rates or trade times.
  ///
  /// The latest refresh attempt controls which live overlays remain available. An older
  /// result cannot resurrect a live quote removed by a newer failed refresh. Equal-date
  /// daily quotes prefer the latest attempt; the receiver wins equal attempt timestamps.
  public func merging(_ other: RateSnapshot) -> RateSnapshot {
    let latest = (checkedAt ?? fetchedAt) >= (other.checkedAt ?? other.fetchedAt) ? self : other
    let older = (checkedAt ?? fetchedAt) >= (other.checkedAt ?? other.fetchedAt) ? other : self
    var daily = older.dailyQuotes ?? older.quotes.filter { $0.value.overlayTimestamp == nil }
    for (code, quote) in latest.dailyQuotes
      ?? latest.quotes.filter({ $0.value.overlayTimestamp == nil })
    where quote.published >= (daily[code]?.published ?? "") {
      daily[code] = quote
    }
    var effective = daily
    for (code, quote) in latest.quotes where quote.overlayTimestamp != nil {
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
      checkedAt: [checkedAt, other.checkedAt].compactMap { $0 }.max())
  }
}
