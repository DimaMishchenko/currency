import Foundation
import Testing

@testable import ExchangeRates

actor MinuteHistoryHTTP: HTTPClient {
  private(set) var urls: [URL] = []
  var shortened = false
  var failing = false
  var missingQuoteMinute = false
  func shorten() { shortened = true }
  func fail() { failing = true }
  func omitQuoteMinute() { missingQuoteMinute = true }

  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    if failing { throw RateError.http(503) }
    if url.host == "cdn.jsdelivr.net" {
      return Data(
        "{\"date\":\"2026-01-05\",\"eur\":{\"usd\":2,\"gbp\":1,\"czk\":50,\"btc\":0.00002}}".utf8)
    }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let assets = try #require(query.first { $0.name == "assets" }?.value).split(separator: ",")
    let start = try historyDate(try #require(query.first { $0.name == "start_time" }?.value))
    var rows: [[String: String]] = []
    for asset in assets {
      for minute in (shortened ? 1433 : 0)..<1440 {
        if missingQuoteMinute && asset == "eth" && minute == 500 { continue }
        rows.append([
          "asset": String(asset),
          "time": start.addingTimeInterval(Double(minute) * 60).ISO8601Format(),
          "ReferenceRateUSD": asset == "eth" ? "10" : "100"
        ])
      }
    }
    return try JSONSerialization.data(withJSONObject: ["data": rows])
  }
}

@Suite struct HistoryCrossRateTests {
  let now = Date(timeIntervalSince1970: 1_767_571_200)

  @Test func cryptoCryptoDividesOnlyAlignedFiveMinuteSamples() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MinuteHistoryHTTP()
    await client.omitQuoteMinute()
    let result = await HistoryService(
      directory: directory, client: client
    )
    .load(base: "BTC", quote: "ETH", range: .day, now: now)
    #expect(result.issue == nil)
    let series = try #require(result.series)
    #expect(series.points.count == 287)
    #expect(
      series.points.allSatisfy { $0.value == 10 && Int($0.date.timeIntervalSince1970) % 300 == 0 })
    #expect(series.source.provider == .coinMetrics)
    #expect(series.source.conversion == nil)
    #expect(series.source.observation == .minuteReference)
    #expect(await client.urls.count == 1)
  }

  @Test func cryptoFiatUsesDatedDailyApproximationAndReciprocal() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MinuteHistoryHTTP()
    let service = HistoryService(directory: directory, client: client)
    let direct = await service.load(base: "BTC", quote: "CZK", range: .day, now: now)
    let inverse = await service.load(base: "CZK", quote: "BTC", range: .day, now: now)
    #expect(direct.issue == nil)
    #expect(inverse.issue == nil)
    #expect(direct.series?.points.allSatisfy { $0.value == 2500 } == true)
    #expect(inverse.series?.points.allSatisfy { $0.value == 0.0004 } == true)
    #expect(
      direct.series?.source.conversion
        == RateConversion(
          provider: .fawaz, published: "2026-01-05", value: 25, base: "USD", quote: "CZK"))
  }

  @Test func shortenedCommunityWindowNeverClaimsTwentyFourHoursOrOverwritesCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MinuteHistoryHTTP()
    let service = HistoryService(directory: directory, client: client)
    await client.shorten()
    let missing = await service.load(base: "BTC", quote: "USD", range: .day, now: now)
    #expect(missing.issue == .unavailable)
    #expect(missing.series == nil)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }
}
