import Foundation

/// A dated historical conversion value.
public struct HistoryPoint: Codable, Sendable, Identifiable, Equatable {
  /// The date used as the stable identity.
  public var id: Date { date }
  /// The quote date.
  public let date: Date
  /// The historical conversion value.
  public let value: Double
  /// Creates an owned history value from validated provider or fixture data.
  public init(date: Date, value: Double) { self.date = date; self.value = value }
}

/// A cached historical time series.
public struct HistorySeries: Codable, Sendable {
  /// The ordered history points.
  public let points: [HistoryPoint]
  /// The provider and aggregation description.
  public let source: RateSource
  /// The time at which the series was fetched.
  public let fetchedAt: Date
  /// Creates an owned history value from validated provider or fixture data.
  public init(points: [HistoryPoint], source: RateSource, fetchedAt: Date) {
    self.points = points; self.source = source; self.fetchedAt = fetchedAt
  }
}

/// The result of loading a historical series.
public struct HistoryResult: Sendable {
  /// The loaded or cached series.
  public let series: HistorySeries?
  /// A recoverable availability or persistence condition.
  public let issue: HistoryIssue?
  /// Creates an owned history value from validated provider or fixture data.
  public init(series: HistorySeries?, issue: HistoryIssue?) {
    self.series = series; self.issue = issue
  }
}
