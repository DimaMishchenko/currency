import CoordinatedFiles
import Foundation

struct HistoryCacheRecord: Codable {
  let series: HistorySeries
  let fiatHistoryPolicyVersion: Int?
  let weeklyHourlyAttemptedAt: Date?

  init(
    series: HistorySeries, fiatHistoryPolicyVersion: Int? = nil,
    weeklyHourlyAttemptedAt: Date? = nil
  ) {
    self.weeklyHourlyAttemptedAt = weeklyHourlyAttemptedAt
    self.series = series
    self.fiatHistoryPolicyVersion = fiatHistoryPolicyVersion
  }

  private enum CodingKeys: String, CodingKey {
    case fiatHistoryPolicyVersion, weeklyHourlyAttemptedAt
  }

  init(from decoder: any Decoder) throws {
    weeklyHourlyAttemptedAt = try decoder.container(keyedBy: CodingKeys.self)
      .decodeIfPresent(Date.self, forKey: .weeklyHourlyAttemptedAt)
    series = try HistorySeries(from: decoder)
    fiatHistoryPolicyVersion = try decoder.container(keyedBy: CodingKeys.self)
      .decodeIfPresent(Int.self, forKey: .fiatHistoryPolicyVersion)
  }

  func encode(to encoder: any Encoder) throws {
    try series.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(fiatHistoryPolicyVersion, forKey: .fiatHistoryPolicyVersion)
    try container.encodeIfPresent(weeklyHourlyAttemptedAt, forKey: .weeklyHourlyAttemptedAt)
  }
}

extension HistoryService {
  static func freshHistory(
    _ series: HistorySeries, range: HistoryRange, now: Date, cacheLifetime: TimeInterval?
  ) -> Bool {
    if range == .week && series.source.observation == .hourlyReference {
      return now.timeIntervalSince(series.fetchedAt) < min(cacheLifetime ?? 3600, 3600)
        && now < nextHour(after: series.fetchedAt)
    }
    let lifetime: TimeInterval = range == .day ? 1800 : (range == .all ? 86400 : 21600)
    return now.timeIntervalSince(series.fetchedAt) < (cacheLifetime ?? lifetime)
      && (range != .day || now < nextHour(after: series.fetchedAt))
  }

  static func recordSuccessfulRefresh(
    at file: URL, originalData: Data?, series: HistorySeries, base: String, quote: String,
    range: HistoryRange, now: Date, cacheLifetime: TimeInterval?, fiatPolicy: Bool,
    weeklyPolicy: Bool = false, weeklyHourlyAttemptedAt: Date? = nil
  ) throws -> HistorySeries {
    try FileCoordination.write(at: file) {
      let currentData = try FileCoordination.dataIfPresent(at: file)
      let currentRecord = currentData.flatMap {
        try? JSONDecoder().decode(HistoryCacheRecord.self, from: $0)
      }
      if currentData != originalData, let current = currentRecord,
        validHistory(
          current.series, base: base, quote: quote, range: range,
          now: max(now, current.series.fetchedAt)),
        freshHistory(
          current.series, range: range, now: max(now, current.series.fetchedAt),
          cacheLifetime: cacheLifetime),
        current.series.fetchedAt > series.fetchedAt
          || (weeklyPolicy && current.series.source.observation == .hourlyReference
            && series.source.observation != .hourlyReference)
          || (fiatPolicy && current.series.source.provider == .frankfurter
            && series.source.provider == .fawaz)
      {
        return current.series
      }
      let hourlyAttempt = [weeklyHourlyAttemptedAt, currentRecord?.weeklyHourlyAttemptedAt]
        .compactMap { $0 }.max()
      try JSONEncoder()
        .encode(
          HistoryCacheRecord(
            series: series, fiatHistoryPolicyVersion: fiatPolicy ? 1 : nil,
            weeklyHourlyAttemptedAt: weeklyPolicy ? hourlyAttempt : nil)
        )
        .write(to: file, options: .atomic)
      return series
    }
  }

  static func recordWeeklyAttempt(
    at file: URL, originalData: Data?, cached: HistorySeries,
    base: String, quote: String, now: Date
  ) throws -> HistorySeries {
    try FileCoordination.write(at: file) {
      guard let data = try FileCoordination.dataIfPresent(at: file) else { return cached }
      guard data == originalData else {
        guard let current = try? JSONDecoder().decode(HistoryCacheRecord.self, from: data),
          validHistory(
            current.series, base: base, quote: quote, range: .week,
            now: max(now, current.series.fetchedAt))
        else { return cached }
        return current.series
      }
      try JSONEncoder().encode(HistoryCacheRecord(series: cached, weeklyHourlyAttemptedAt: now))
        .write(to: file, options: .atomic)
      return cached
    }
  }

  static func recordFailedFiatRefresh(
    at file: URL, originalData: Data, cached: HistorySeries,
    base: String, quote: String, range: HistoryRange, now: Date
  ) throws -> HistorySeries {
    try FileCoordination.write(at: file) {
      guard let currentData = try FileCoordination.dataIfPresent(at: file) else { return cached }
      guard currentData == originalData else {
        guard let current = try? JSONDecoder().decode(HistoryCacheRecord.self, from: currentData),
          validHistory(
            current.series, base: base, quote: quote, range: range,
            now: max(now, current.series.fetchedAt))
        else { return cached }
        return current.series
      }
      try JSONEncoder().encode(HistoryCacheRecord(series: cached, fiatHistoryPolicyVersion: 1))
        .write(to: file, options: .atomic)
      return cached
    }
  }

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
    let hourly =
      range == .week && supportsWeeklyHourly(base: base, quote: quote)
      && series.source.provider == .coinMetrics && series.source.observation == .hourlyReference
    let expected: RateProviderID = range == .day ? .coinMetrics : .fawaz
    let observation: RateObservation =
      range == .day ? .minuteReference : range == .all ? .monthlyReference : .dailyReference
    guard
      (hourly || series.source.provider == expected
        || (range == .all && [.coinMetrics, .frankfurter].contains(series.source.provider))
        || (range != .day && range != .all && usesFiatHistory(base: base, quote: quote)
          && series.source.provider == .frankfurter)),
      (hourly || series.source.observation == observation),
      series.points.count >= 2, series.fetchedAt <= now,
      series.points.allSatisfy({ $0.value.isFinite && $0.value > 0 && $0.date <= series.fetchedAt }
      ),
      zip(series.points, series.points.dropFirst()).allSatisfy({ $0.date < $1.date })
    else { return false }
    if hourly { return coversWeek(series.points, ending: hourEndpoint(series.fetchedAt)) }
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
