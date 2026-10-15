import Foundation

/// Minute cryptocurrency reference rates normalized using the Fawaz daily EUR/USD quote.
public struct CoinMetricsProvider: RateProvider {
  private let metrics: CoinMetricsClient
  private let daily: any RateProvider
  private let now: @Sendable () -> Date

  public init(client: any HTTPClient = NetworkClient()) {
    metrics = CoinMetricsClient(client: client)
    daily = FawazProvider(client: client)
    now = { .now }
  }

  init(metrics: CoinMetricsClient, daily: any RateProvider, now: @escaping @Sendable () -> Date) {
    self.metrics = metrics
    self.daily = daily
    self.now = now
  }

  public func fetch() async throws -> [String: ExchangeRate] {
    let time = now()
    async let observations = metrics.observations(
      assets: Array(CurrencyCatalog.crypto), start: time.addingTimeInterval(-600), end: time)
    async let dailyQuotes = daily.fetch()
    let (points, quotes) = try await (observations, dailyQuotes)
    try Task.checkCancellation()
    guard let usd = quotes["USD"], usd.value > 0, !usd.value.isNaN,
      let published = CoinMetricsClient.date(usd.published + "T00:00:00Z"),
      published <= time, time.timeIntervalSince(published) < 3 * 86400
    else { throw RateError.invalidData }
    let conversion = RateConversion(
      provider: usd.source.provider, published: usd.published, value: usd.value,
      base: "EUR", quote: "USD")
    var result: [String: ExchangeRate] = [:]
    for (code, values) in points {
      guard let latest = values.last,
        latest.date <= time, time.timeIntervalSince(latest.date) <= 600,
        let price = Decimal(string: String(latest.value)), price > 0, !price.isNaN
      else { continue }
      let value = usd.value / price
      guard value > 0, !value.isNaN else { continue }
      result[code] = ExchangeRate(
        value, published: String(latest.date.ISO8601Format().prefix(10)),
        source: .init(
          provider: .coinMetrics, observation: .minuteReference, timeZone: .gmt,
          conversion: conversion),
        observedAt: latest.date, retrievedAt: time)
    }
    guard !result.isEmpty else { throw RateError.invalidData }
    return result
  }
}
