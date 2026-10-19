import Foundation

extension HistoryService {
  static func supportsWeeklyHourly(base: String, quote: String) -> Bool {
    base != quote && CurrencyCatalog.codes.contains(base) && CurrencyCatalog.codes.contains(quote)
      && (CurrencyCatalog.crypto.contains(base) || CurrencyCatalog.crypto.contains(quote))
  }

  static func hourEndpoint(_ date: Date) -> Date {
    Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 3600) * 3600)
  }

  static func coversWeek(_ points: [HistoryPoint], ending end: Date) -> Bool {
    guard let first = points.first, let last = points.last, points.count >= 160,
      first.date >= end.addingTimeInterval(-7 * 86400),
      first.date <= end.addingTimeInterval(-7 * 86400 + 7200),
      last.date >= end.addingTimeInterval(-10800), last.date <= end,
      points.allSatisfy({
        $0.value.isFinite && $0.value > 0
          && $0.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600) == 0
      })
    else { return false }
    return zip(points, points.dropFirst())
      .allSatisfy {
        $1.date > $0.date && $1.date.timeIntervalSince($0.date) <= 10800
      }
  }

  func weeklyHourly(
    base: String, quote: String, now: Date
  ) async throws
    -> ([HistoryPoint], RateSource)
  {
    let end = Self.hourEndpoint(now)
    let assets = [base, quote].filter { CurrencyCatalog.crypto.contains($0) }
    let observations = try await CoinMetricsClient(client: client, directory: directory)
      .observations(
        assets: assets, start: end.addingTimeInterval(-7 * 86400), end: end, frequency: "1h")
    guard assets.allSatisfy({ Self.coversWeek(observations[$0, default: []], ending: end) })
    else { throw RateError.unavailable }
    let byAsset = observations.mapValues {
      Dictionary($0.map { ($0.date, $0.value) }, uniquingKeysWith: { _, last in last })
    }
    let dates = observations[assets[0], default: []].map(\.date)
    let other = [base, quote].first { !CurrencyCatalog.crypto.contains($0) && $0 != "USD" }
    var usdValues: [String: Double] = [:]
    var conversion: RateConversion?
    if let other {
      let canonical = ["GGP", "IMP", "JEP"].contains(other) ? "GBP" : other
      for day in Set(dates.map { String($0.ISO8601Format().prefix(10)) }).sorted() {
        let rates = try await Self.dailySnapshot(client: client, directory: directory, day: day)
        guard let usd = rates["USD"]?.value, let fx = rates[canonical]?.value,
          usd > 0, fx > 0
        else { throw RateError.unavailable }
        usdValues[day] = NSDecimalNumber(decimal: usd / fx).doubleValue
        conversion = RateConversion(
          provider: .fawaz, published: day, value: fx / usd, base: "USD", quote: other)
      }
    }
    let points = dates.compactMap { date -> HistoryPoint? in
      let day = String(date.ISO8601Format().prefix(10))
      let a =
        CurrencyCatalog.crypto.contains(base)
        ? byAsset[base]?[date]
        : (base == "USD" ? 1 : usdValues[day])
      let b =
        CurrencyCatalog.crypto.contains(quote)
        ? byAsset[quote]?[date]
        : (quote == "USD" ? 1 : usdValues[day])
      guard let a, let b, a > 0, b > 0 else { return nil }
      return HistoryPoint(date: date, value: a / b)
    }
    guard Self.coversWeek(points, ending: end) else { throw RateError.unavailable }
    return (
      points,
      RateSource(
        provider: .coinMetrics, observation: .hourlyReference, timeZone: .gmt,
        conversion: conversion,
        contributingProviders: other == nil ? nil : [.fawaz])
    )
  }
}
