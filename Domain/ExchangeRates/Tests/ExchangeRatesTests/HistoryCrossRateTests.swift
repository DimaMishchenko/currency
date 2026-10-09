import Foundation
import Testing

@testable import ExchangeRates

private actor CrossRateHTTP: HTTPClient {
  var urls: [URL] = []
  private var failEthereum = false

  func failEthereumRequests() { failEthereum = true }

  func get(_ url: URL) async throws -> Data {
    urls.append(url)
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
    throw RateError.invalidData
  }
}

@Suite struct HistoryCrossRateTests {
  private let now = Date(timeIntervalSince1970: 1_767_571_200)

  @Test func cryptoCryptoDividesMatchingHourlyClosesForOneDay() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    let result = await HistoryService(
      directory: directory, client: client, policy: .coinbaseEnhanced
    )
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

  @Test(arguments: [("USDC", "BTC"), ("BTC", "USDC")])
  func cryptoWithoutBothDollarMarketsJoinsMatchingHourlyEuroCloses(
    base: String, quote: String
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    #expect(HistoryService.supportsIntraday(base: base, quote: quote))
    let result = await HistoryService(
      directory: directory, client: client, policy: .coinbaseEnhanced
    )
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

  @Test func failedHourlyQuoteLegNeverSavesPartialSeries() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    await client.failEthereumRequests()
    let result = await HistoryService(
      directory: directory, client: client, policy: .coinbaseEnhanced
    )
    .load(base: "BTC", quote: "ETH", range: .day, now: now)
    #expect(result.series == nil)
    #expect(result.issue == .unavailable)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }

  @Test func cryptoFiatWithoutHourlyMarketReturnsUnsupportedWithoutRequestOrCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CrossRateHTTP()
    let result = await HistoryService(
      directory: directory, client: client, policy: .coinbaseEnhanced
    )
    .load(base: "BTC", quote: "CZK", range: .day, now: now)
    #expect(result.series == nil)
    #expect(result.issue == .intradayUnavailable)
    #expect(await client.urls.isEmpty)
  }

}
