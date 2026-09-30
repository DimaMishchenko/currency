import Conversion
import ExchangeRates
import Foundation

/// A history pair follows app selections unless a currency is explicitly overridden.
public struct HistoryWidgetPair: Sendable, Equatable {
  /// Resolved base currency code.
  public let base: String
  /// Resolved comparison currency, absent when the app list is empty.
  public let quote: String?

  /// Nil overrides follow the app base and first displayed destination independently.
  public init(app: ConverterState, base: String? = nil, quote: String? = nil) {
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

  /// Whether the supported pair can load completed hourly observations.
  public var supportsIntradayHistory: Bool {
    guard let request = historyRequest else { return false }
    return HistoryService.supportsIntraday(base: request.base, quote: request.quote)
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

  /// Validates history for rendering without substituting live or sample rates.
  public init(pair: HistoryWidgetPair, range: HistoryRange, result: HistoryResult) {
    self.pair = pair
    self.range = range
    let inverted = pair.historyRequest?.inverted == true
    let points =
      result.series?.points
      .map {
        HistoryPoint(date: $0.date, value: inverted ? 1 / $0.value : $0.value)
      } ?? []
    let valid =
      pair.isSupported && points.count >= 2
      && points.allSatisfy { $0.value.isFinite && $0.value > 0 }
      && zip(points, points.dropFirst()).allSatisfy { $0.date < $1.date }
    series =
      valid
      ? result.series.map {
        HistorySeries(points: points, source: $0.source, fetchedAt: $0.fetchedAt)
      }
      : nil
    issue = !pair.isSupported ? .unsupportedPair : valid ? result.issue : .unavailable
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

  /// Supported crypto refreshes follow UTC hours; other pairs follow daily cache expiry.
  public func nextRefresh(after now: Date) -> Date {
    let hourly = pair.supportsIntradayHistory
    let interval: TimeInterval = hourly ? 3600 : 86_400
    if let fetchedAt = series?.fetchedAt, fetchedAt <= now, issue != .usingCachedSeries {
      let expiry =
        hourly
        ? HistoryService.nextHour(after: fetchedAt) : fetchedAt.addingTimeInterval(interval)
      if expiry > now { return expiry }
    }
    return hourly ? HistoryService.nextHour(after: now) : now.addingTimeInterval(interval)
  }
}
