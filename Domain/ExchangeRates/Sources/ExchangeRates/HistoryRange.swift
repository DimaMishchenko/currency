/// Supported historical intervals. A year follows the UTC Gregorian calendar.
public enum HistoryRange: Int, Sendable, CaseIterable {
  /// The preceding twenty-four hours, using completed hourly candles.
  case day = 1
  /// The preceding seven days.
  case week = 7
  /// The preceding thirty days.
  case month = 30
  /// The preceding ninety days.
  case quarter = 90
  /// The preceding calendar year, including leap-day adjustment.
  case year = 365
  /// From January 1 of the current UTC Gregorian year.
  case yearToDate = -1
  /// All provider history, aggregated monthly.
  case all = 0
}
