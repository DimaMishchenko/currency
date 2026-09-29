import Foundation
import Testing

@testable import ExchangeRates

private struct CrossRateRow: Encodable {
  let date: String
  let base: String
  let quote: String
  let rate: Double
}

private actor CrossRateHTTP: HTTPClient {
  var urls: [URL] = []
  private var failFiat = false
  private var failEthereum = false

  func failFiatRequests() { failFiat = true }
  func failEthereumRequests() { failEthereum = true }

  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    if url.host == "api.frankfurter.dev" {
      if failFiat { throw RateError.http(503) }
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let base = query.first { $0.name == "base" }?.value ?? ""
      let quote = query.first { $0.name == "quotes" }?.value ?? ""
      let values: (Double, Double) =
        switch (base, quote) {
        case ("USD", "EUR"): (0.8, 0.9)
        case ("USD", "XAU"): (0.0005, 0.0004)
        case ("XAU", "EUR"): (1_500, 1_600)
        case ("XAU", "XAG"): (50, 51)
        default: throw RateError.invalidData
        }
      return try JSONEncoder()
        .encode([
          CrossRateRow(date: "2026-01-02", base: base, quote: quote, rate: values.0),
          CrossRateRow(date: "2026-01-04", base: base, quote: quote, rate: values.1)
        ])
    }
    let day = 86_400.0
    let start = Date(timeIntervalSince1970: 1_767_312_000).timeIntervalSince1970
    let isEthereum = url.path == "/products/ETH-USD/candles"
    if isEthereum && failEthereum { throw RateError.http(503) }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    if query.contains(URLQueryItem(name: "granularity", value: "3600")) {
      let start = Date(timeIntervalSince1970: 1_767_484_800).timeIntervalSince1970
      if url.path == "/products/USDC-EUR/candles" {
        return try JSONEncoder()
          .encode([
            [start + 3_600, 1, 200, 1, 1, 1],
            [start + 7_200, 1, 200, 1, 2, 1],
            [start + 10_800, 1, 200, 1, 3, 1]
          ])
      }
      return try JSONEncoder()
        .encode([
          [start + 3_600, 1, 200, 1, isEthereum ? 10 : 100, 1],
          [start + 7_200, 1, 200, 1, isEthereum ? 20 : 110, 1]
        ])
    }
    if isEthereum {
      return try JSONEncoder()
        .encode([
          [start, 1, 50, 1, 10, 1], [start + 2 * day, 1, 50, 1, 30, 1]
        ])
    }
    return try JSONEncoder()
      .encode([
        [start, 1, 200, 1, 100, 1],
        [start + day, 1, 200, 1, 110, 1],
        [start + 2 * day, 1, 200, 1, 120, 1]
      ])
  }
}

@Suite struct HistoryCrossRateTests {
  private let now = Date(timeIntervalSince1970: 1_767_571_200)

  @Test func cryptoFiatUsesCoinbaseUsdAndMatchingHistoricalFiatDates() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    let service = HistoryService(directory: directory, client: client)
    let result = await service.load(base: "BTC", quote: "EUR", range: .month, now: now)
    #expect(result.issue == nil)
    #expect(result.series?.points.map(\.value) == [80, 108])
    #expect(result.series?.source.provider == .custom("Coinbase + Frankfurter"))
    #expect(result.series?.source.observation == .unspecified)
    let urls = await client.urls
    #expect(urls.count == 2)
    #expect(urls.contains { $0.path == "/products/BTC-USD/candles" })
    let fiatURL = try #require(urls.first { $0.host == "api.frankfurter.dev" })
    let query = try #require(
      URLComponents(url: fiatURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.contains(URLQueryItem(name: "base", value: "USD")))
    #expect(query.contains(URLQueryItem(name: "quotes", value: "EUR")))
    #expect(!query.contains(where: { $0.name == "group" }))
    let cached = await service.load(base: "BTC", quote: "EUR", range: .month, now: now)
    #expect(cached.series?.points == result.series?.points)
    #expect(await client.urls.count == 2)
  }

  @Test func cryptoCryptoDividesOnlyMatchingDailyCloses() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "ETH", range: .month, now: now)
    #expect(result.issue == nil)
    #expect(result.series?.points.map(\.value) == [10, 4])
    #expect(result.series?.source.provider == .coinbase)
    let urls = await client.urls
    #expect(urls.count == 2)
    #expect(urls.contains { $0.path == "/products/BTC-USD/candles" })
    #expect(urls.contains { $0.path == "/products/ETH-USD/candles" })
  }

  @Test func cryptoCryptoDividesMatchingHourlyClosesForOneDay() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "ETH", range: .day, now: now)
    #expect(result.issue == nil)
    #expect(result.series?.points.map(\.value) == [10, 5.5])
    #expect(result.series?.source.observation == .hourlyClose)
    #expect(await client.urls.count == 2)
    let urls = await client.urls
    #expect(Set(urls.map(\.path)) == ["/products/BTC-USD/candles", "/products/ETH-USD/candles"])
    #expect(
      urls.allSatisfy { url in
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .contains(
            URLQueryItem(name: "granularity", value: "3600")) == true
      })
  }

  @Test func failedCryptoQuoteLegNeverSavesPartialSeries() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    await client.failEthereumRequests()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "ETH", range: .month, now: now)
    #expect(result.series == nil)
    #expect(result.issue == .unavailable)
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("history-BTC-ETH-30.json").path))
  }

  @Test(arguments: [("USDC", "BTC"), ("BTC", "USDC")])
  func cryptoWithoutBothDollarMarketsJoinsMatchingHourlyEuroCloses(
    base: String, quote: String
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    #expect(HistoryService.supportsIntraday(base: base, quote: quote))
    let result = await HistoryService(directory: directory, client: client)
      .load(base: base, quote: quote, range: .day, now: now)
    #expect(result.issue == nil)
    let values = try #require(result.series?.points.map(\.value))
    #expect(values.count == 2)
    #expect(values == (base == "USDC" ? [1.0 / 100, 2.0 / 110] : [100, 55]))
    #expect(
      result.series?.source == .init(provider: .coinbase, observation: .hourlyClose, timeZone: .gmt)
    )
    let urls = await client.urls
    #expect(Set(urls.map(\.path)) == ["/products/USDC-EUR/candles", "/products/BTC-EUR/candles"])
    #expect(
      urls.allSatisfy { url in
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .contains(
            URLQueryItem(name: "granularity", value: "3600")) == true
      })
  }

  @Test func cryptoMetalUsesHistoricalUsdMetalReferences() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = await HistoryService(directory: directory, client: CrossRateHTTP())
      .load(base: "BTC", quote: "XAU", range: .month, now: now)
    #expect(result.issue == nil)
    let values = try #require(result.series?.points.map(\.value))
    #expect(values.count == 2)
    #expect(abs(values[0] - 0.05) < 0.0000001)
    #expect(abs(values[1] - 0.048) < 0.0000001)
  }

  @Test func metalFiatUsesFrankfurterPairDirectly() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "XAU", quote: "EUR", range: .month, now: now)
    #expect(result.issue == nil)
    #expect(result.series?.points.map(\.value) == [1_500, 1_600])
    #expect(result.series?.source.provider == .frankfurter)
    #expect(await client.urls.count == 1)
  }

  @Test func metalMetalUsesFrankfurterPairDirectly() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = await HistoryService(directory: directory, client: CrossRateHTTP())
      .load(base: "XAU", quote: "XAG", range: .month, now: now)
    #expect(result.issue == nil)
    #expect(result.series?.points.map(\.value) == [50, 51])
  }

  @Test func monthlySamplingFollowsCrossRateJoin() throws {
    let january = try #require(ISO8601DateFormatter().date(from: "2026-01-30T00:00:00Z"))
    let next = january.addingTimeInterval(86_400)
    let february = january.addingTimeInterval(2 * 86_400)
    let candles = [
      HistoryPoint(date: january, value: 100),
      HistoryPoint(date: next, value: 200),
      HistoryPoint(date: february, value: 300)
    ]
    let rates = [
      HistoryPoint(date: january, value: 0.8),
      HistoryPoint(date: february, value: 0.9)
    ]
    let joined = try HistoryService.convertDailyCloses(candles, rates: rates)
    #expect(HistoryService.monthlyCloses(joined).map(\.value) == [80, 270])
  }

  @Test func cryptoFiatWithoutHourlyMarketReturnsUnsupportedWithoutRequestOrCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "BTC", quote: "CZK", range: .day, now: now)
    #expect(result.series == nil)
    #expect(result.issue == .intradayUnavailable)
    #expect(await client.urls.isEmpty)
  }

  @Test func crossRateFailureUsesOnlyPreviousCompletePairCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    let service = HistoryService(directory: directory, client: client)
    let first = await service.load(base: "BTC", quote: "EUR", range: .month, now: now)
    await client.failFiatRequests()
    let expired = await service.load(
      base: "BTC", quote: "EUR", range: .month, now: now.addingTimeInterval(21_600))
    #expect(expired.series?.points == first.series?.points)
    #expect(expired.issue == .usingCachedSeries)
    let file = directory.appendingPathComponent("history-BTC-EUR-30.json")
    #expect(
      try JSONDecoder().decode(HistorySeries.self, from: Data(contentsOf: file)).points
        == first.series?.points)
  }
}
