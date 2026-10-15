import Foundation

struct HistoryCacheRecord: Codable {
  let series: HistorySeries
  let fiatHistoryPolicyVersion: Int?

  init(series: HistorySeries, fiatHistoryPolicyVersion: Int? = nil) {
    self.series = series
    self.fiatHistoryPolicyVersion = fiatHistoryPolicyVersion
  }

  private enum CodingKeys: String, CodingKey {
    case fiatHistoryPolicyVersion
  }

  init(from decoder: any Decoder) throws {
    series = try HistorySeries(from: decoder)
    fiatHistoryPolicyVersion = try decoder.container(keyedBy: CodingKeys.self)
      .decodeIfPresent(Int.self, forKey: .fiatHistoryPolicyVersion)
  }

  func encode(to encoder: any Encoder) throws {
    try series.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(fiatHistoryPolicyVersion, forKey: .fiatHistoryPolicyVersion)
  }
}

extension HistoryService {
  static func historyStart(range: HistoryRange, at date: Date, calendar: Calendar) -> Date? {
    switch range {
    case .year: calendar.date(byAdding: .year, value: -1, to: date)
    case .yearToDate:
      calendar.date(
        from: DateComponents(year: calendar.component(.year, from: date), month: 1, day: 1))
    case .all: nil
    default: date.addingTimeInterval(-Double(range.rawValue) * 86400)
    }
  }

  static func validHistory(
    _ series: HistorySeries, base: String, quote: String, range: HistoryRange, now: Date
  ) -> Bool {
    let expected: RateProviderID = range == .day ? .coinMetrics : .fawaz
    let observation: RateObservation =
      range == .day ? .minuteReference : range == .all ? .monthlyReference : .dailyReference
    guard
      (series.source.provider == expected
        || (range == .all && [.coinMetrics, .frankfurter].contains(series.source.provider))
        || (range != .day && range != .all && usesFiatHistory(base: base, quote: quote)
          && series.source.provider == .frankfurter)),
      series.source.observation == observation,
      series.points.count >= 2, series.fetchedAt <= now,
      series.points.allSatisfy({ $0.value.isFinite && $0.value > 0 && $0.date <= series.fetchedAt }
      ),
      zip(series.points, series.points.dropFirst()).allSatisfy({ $0.date < $1.date })
    else { return false }
    if range == .day {
      let end = Date(timeIntervalSince1970: floor(series.fetchedAt.timeIntervalSince1970 / 60) * 60)
      return coversDay(series.points, ending: end)
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    if range == .all {
      guard let currentMonth = calendar.dateInterval(of: .month, for: series.fetchedAt)?.start,
        series.points.allSatisfy({ $0.date < currentMonth })
      else { return false }
      let months = series.points.map { calendar.dateComponents([.year, .month], from: $0.date) }
      return Set(months).count == months.count
    }
    guard let start = historyStart(range: range, at: series.fetchedAt, calendar: calendar),
      series.points.allSatisfy({ $0.date >= calendar.startOfDay(for: start) })
    else { return false }
    let days = series.points.map { calendar.startOfDay(for: $0.date) }
    guard Set(days).count == days.count else { return false }
    return range != .yearToDate
      || calendar.component(.year, from: series.fetchedAt) == calendar.component(.year, from: now)
  }
}
