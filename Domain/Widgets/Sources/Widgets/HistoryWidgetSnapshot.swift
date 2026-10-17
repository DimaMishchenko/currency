import Conversion
import ExchangeRates
import Foundation

/// A history pair follows app selections unless a currency is explicitly overridden.
public struct HistoryWidgetPair: Sendable, Equatable {
  /// Resolved base currency code.
  public let base: String
  /// Resolved comparison currency, absent when the app list is empty.
  public let quote: String?
  /// The app-selected mass unit for both metal currencies.
  public let metalUnit: MetalUnit

  /// Nil overrides follow the app base and first displayed destination independently.
  public init(
    app: ConverterState, base: String? = nil, quote: String? = nil
  ) {
    metalUnit = app.metalUnit
    self.base = base ?? app.source
    self.quote = quote ?? app.destinationRows.first?.code
  }

  /// Whether a selected Local row still needs an eligible location observation.
  public var needsLocalCurrency: Bool {
    base == WidgetSelection.localID || quote == WidgetSelection.localID
  }

  /// The source pair and direction supported by the history providers.
  public var historyRequest: (base: String, quote: String, inverted: Bool)? {
    guard let quote, base != quote,
      CurrencyCatalog.codes.contains(base), CurrencyCatalog.codes.contains(quote)
    else { return nil }
    if CurrencyCatalog.crypto.contains(base) {
      return (base, quote, false)
    }
    if CurrencyCatalog.crypto.contains(quote) {
      return (quote, base, true)
    }
    return (base, quote, false)
  }

  /// Whether a historical series can be loaded for the displayed pair.
  public var isSupported: Bool { historyRequest != nil }

  /// Whether the supported pair can load intraday reference observations.
  public var supportsIntradayHistory: Bool {
    guard let request = historyRequest else { return false }
    return HistoryService.supportsIntraday(base: request.base, quote: request.quote)
  }
  /// Replaces an unavailable saved intraday range with daily one-month history.
  public func normalizedRange(_ range: HistoryRange) -> HistoryRange {
    range == .day && !supportsIntradayHistory ? .month : range
  }
}

/// Historical observations and their provenance, kept separate from live conversion rates.
public struct HistoryWidgetSnapshot: Sendable {
  /// Resolved currencies represented by this series.
  public let pair: HistoryWidgetPair
  /// Requested historical interval.
  public let range: HistoryRange
  /// Validated chronological observations, absent for unavailable history.
  public let series: HistorySeries?
  /// Availability or cache warning supplied by the history loader.
  public let issue: HistoryIssue?

  /// Validates a quote-aligned history result before applying presentation direction and units.
  public init(pair: HistoryWidgetPair, range: HistoryRange, result: HistoryResult) {
    self.pair = pair
    self.range = range
    guard pair.isSupported, let combined = result.series, Self.isValid(combined) else {
      series = nil
      issue = pair.isSupported ? .unavailable : .unsupportedPair
      return
    }
    let inverted = pair.historyRequest?.inverted == true
    let factor = NSDecimalNumber(
      decimal: pair.metalUnit.rateFactor(from: pair.base, to: pair.quote ?? pair.base)
    )
    .doubleValue
    let points =
      combined.points.map {
        HistoryPoint(date: $0.date, value: (inverted ? 1 / $0.value : $0.value) * factor)
      }
    let valid =
      points.allSatisfy { $0.value.isFinite && $0.value > 0 }
    series =
      valid
      ? HistorySeries(points: points, source: combined.source, fetchedAt: combined.fetchedAt)
      : nil
    issue = valid ? result.issue : .unavailable
  }

  private static func isValid(_ series: HistorySeries) -> Bool {
    series.points.count >= 2
      && series.points.allSatisfy {
        $0.value.isFinite && $0.value > 0 && $0.date <= series.fetchedAt
      }
      && zip(series.points, series.points.dropFirst()).allSatisfy { $0.date < $1.date }
  }

  /// The rate and date always come from the same last observation shown by the graph.
  public var latest: HistoryPoint? { series?.points.last }

  /// Fractional change over the plotted period, rounded to the displayed basis point.
  /// Tiny changes display as neutral instead of a colored signed zero.
  public var change: Double? {
    guard let first = series?.points.first, let latest else { return nil }
    let value = (latest.value / first.value - 1) * 10_000
    guard value.isFinite else { return nil }
    return value.rounded() / 10_000
  }

  /// Pairs with intraday history refresh at UTC hour boundaries for every chart range.
  public func nextRefresh(after now: Date) -> Date {
    if pair.supportsIntradayHistory { return HistoryService.nextHour(after: now) }
    let interval: TimeInterval = 86_400
    if let fetchedAt = series?.fetchedAt, fetchedAt <= now, issue != .usingCachedSeries {
      let expiry = fetchedAt.addingTimeInterval(interval)
      if expiry > now { return expiry }
    }
    return now.addingTimeInterval(interval)
  }
}
