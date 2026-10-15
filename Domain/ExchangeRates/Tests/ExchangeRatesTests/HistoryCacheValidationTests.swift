import Foundation
import Testing

@testable import ExchangeRates

private actor HistoryCacheHTTP: HTTPClient {
  private(set) var urls: [URL] = []
  let failing: Bool
  let invalid: Bool
  let delayed: Bool
  init(failing: Bool = false, invalid: Bool = false, delayed: Bool = false) {
    self.failing = failing
    self.invalid = invalid
    self.delayed = delayed
  }
  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    if delayed { try await Task.sleep(for: .seconds(10)) }
    if failing { throw RateError.http(503) }
    guard url.host == "api.frankfurter.dev" else { throw RateError.http(503) }
    if invalid { return Data("[]".utf8) }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    func value(_ key: String) -> String { query.first { $0.name == key }!.value! }
    let start = try historyDate(value("from") + "T00:00:00Z")
    let end = try historyDate(value("to") + "T00:00:00Z")
    let days = Int(end.timeIntervalSince(start) / 86400)
    let rows: [[String: Any]] = (0...days)
      .flatMap { offset in
        value("quotes").split(separator: ",")
          .map { code in
            [
              "date": String(
                start.addingTimeInterval(Double(offset) * 86400).ISO8601Format().prefix(10)),
              "base": "EUR", "quote": String(code),
              "rate": code == "USD" ? 2 : 7.3 + Double(offset) / 1000
            ]
          }
      }
    return try JSONSerialization.data(withJSONObject: rows)
  }
}

@Suite struct HistoryCacheValidationTests {
  let now = Date(timeIntervalSince1970: 1_792_065_600)

  func flatSeries(at date: Date, provider: RateProviderID = .fawaz) -> HistorySeries {
    HistorySeries(
      points: [
        .init(date: date.addingTimeInterval(-2 * 86400), value: 3.6725),
        .init(date: date.addingTimeInterval(-86400), value: 3.6725)
      ], source: .init(provider: provider, observation: .dailyReference, timeZone: .gmt),
      fetchedAt: date)
  }

  func save(_ series: HistorySeries, directory: URL, range: HistoryRange = .month) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("history-v3-USD-AED-\(range.rawValue).json")
    try JSONEncoder().encode(series).write(to: file)
    return file
  }

  @Test func legacyFlatFiatCacheRefreshesPreferredProvider() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = try save(flatSeries(at: now), directory: directory)
    let client = HistoryCacheHTTP()
    let result = await HistoryService(directory: directory, client: client)
      .load(base: "USD", quote: "AED", range: .month, now: now)
    #expect(result.issue == nil)
    #expect(result.series?.source.provider == .frankfurter)
    #expect(await client.urls.count == 1)
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    #expect(object["fiatHistoryPolicyVersion"] as? Int == 1)
    #expect(
      try JSONDecoder().decode(HistorySeries.self, from: Data(contentsOf: file)).points.count == 31)
  }

  @Test func failedLegacyRefreshPreservesFlatCacheAndRetriesOnlyOnce() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let saved = flatSeries(at: now)
    let file = try save(saved, directory: directory)
    let client = HistoryCacheHTTP(failing: true)
    let first = await HistoryService(directory: directory, client: client)
      .load(base: "USD", quote: "AED", range: .month, now: now)
    #expect(first.issue == .usingCachedSeries)
    #expect(first.series?.points == saved.points)
    #expect(first.series?.fetchedAt == saved.fetchedAt)
    #expect(await client.urls.count == 2)
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    #expect(object["fiatHistoryPolicyVersion"] as? Int == 1)
    let second = await HistoryService(directory: directory, client: client)
      .load(base: "USD", quote: "AED", range: .month, now: now.addingTimeInterval(60))
    #expect(second.issue == nil)
    #expect(second.series?.points == saved.points)
    #expect(await client.urls.count == 2)
  }

  @Test(arguments: ["wrongRange", "afterFetch", "duplicateDay", "currentMonth", "duplicateMonth"])
  func invalidCacheIsRejectedAndRepaired(kind: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let range: HistoryRange = kind.contains("Month") ? .all : .month
    let points: [HistoryPoint]
    switch kind {
    case "wrongRange":
      points = [
        .init(date: now.addingTimeInterval(-90 * 86400), value: 2),
        .init(date: now.addingTimeInterval(-89 * 86400), value: 2)
      ]
    case "afterFetch":
      points = [
        .init(date: now.addingTimeInterval(-86400), value: 2),
        .init(date: now.addingTimeInterval(30), value: 2)
      ]
    case "duplicateDay":
      points = [
        .init(date: now.addingTimeInterval(-86400), value: 2),
        .init(date: now.addingTimeInterval(-86300), value: 2)
      ]
    case "currentMonth":
      points = [
        .init(date: now.addingTimeInterval(-40 * 86400), value: 2),
        .init(date: now.addingTimeInterval(-86400), value: 2)
      ]
    default:
      points = [
        .init(date: now.addingTimeInterval(-40 * 86400), value: 2),
        .init(date: now.addingTimeInterval(-39 * 86400), value: 2)
      ]
    }
    let series = HistorySeries(
      points: points,
      source: .init(
        provider: .frankfurter, observation: range == .all ? .monthlyReference : .dailyReference),
      fetchedAt: now)
    let file = try save(series, directory: directory, range: range)
    let original = try Data(contentsOf: file)
    let failed = await HistoryService(directory: directory, client: HistoryCacheHTTP(failing: true))
      .load(base: "USD", quote: "AED", range: range, now: now.addingTimeInterval(60))
    if range != .all {
      #expect(failed.series == nil)
      #expect(failed.issue == .unavailable)
      #expect(try Data(contentsOf: file) == original)
    } else {
      #expect(failed.series?.points != points)
    }
    let repaired = await HistoryService(directory: directory, client: HistoryCacheHTTP())
      .load(base: "USD", quote: "AED", range: range, now: now.addingTimeInterval(60))
    #expect(repaired.issue == nil)
    #expect(repaired.series?.points != points)
  }

  @Test func currentFiatPolicyAndLegacyPreferredCacheRemainFresh() async throws {
    for provider in [RateProviderID.fawaz, .frankfurter] {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let saved = flatSeries(at: now, provider: provider)
      let file = try save(saved, directory: directory)
      if provider == .fawaz {
        try JSONEncoder().encode(HistoryCacheRecord(series: saved, fiatHistoryPolicyVersion: 1))
          .write(to: file)
      }
      let client = HistoryCacheHTTP(failing: true)
      let result = await HistoryService(directory: directory, client: client)
        .load(base: "USD", quote: "AED", range: .month, now: now)
      #expect(result.issue == nil)
      #expect(result.series?.points == saved.points)
      #expect(await client.urls.isEmpty)
    }
  }

  @Test func cancellationDoesNotStampLegacyCacheOrStartFallback() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let saved = flatSeries(at: now)
    let file = try save(saved, directory: directory)
    let original = try Data(contentsOf: file)
    let client = HistoryCacheHTTP(delayed: true)
    let service = HistoryService(directory: directory, client: client)
    let task = Task { await service.load(base: "USD", quote: "AED", range: .month, now: now) }
    for _ in 0..<300 {
      if await !client.urls.isEmpty { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await client.urls.count == 1)
    task.cancel()
    let result = await task.value
    #expect(result.issue == .usingCachedSeries)
    #expect(result.series?.points == saved.points)
    #expect(await client.urls.count == 1)
    #expect(try Data(contentsOf: file) == original)
  }

  @Test func sharedValidationPreservesSparseConstantPublicationTimes() {
    let series = flatSeries(at: now)
    #expect(HistoryService.validHistory(series, base: "USD", quote: "AED", range: .month, now: now))
    let invalid = HistorySeries(
      points: [
        .init(date: now.addingTimeInterval(-90 * 86400), value: 3.6725),
        .init(date: now.addingTimeInterval(-89 * 86400), value: 3.6725)
      ], source: series.source, fetchedAt: now)
    #expect(
      !HistoryService.validHistory(invalid, base: "USD", quote: "AED", range: .month, now: now))
  }

  @Test func invalidDownloadNeverOverwritesCompatibleSavedSeries() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let saved = flatSeries(at: now.addingTimeInterval(-21601), provider: .frankfurter)
    let file = try save(saved, directory: directory)
    let original = try Data(contentsOf: file)
    let result = await HistoryService(directory: directory, client: HistoryCacheHTTP(invalid: true))
      .load(base: "USD", quote: "AED", range: .month, now: now)
    #expect(result.issue == .usingCachedSeries)
    #expect(result.series?.points == saved.points)
    #expect(try Data(contentsOf: file) == original)
  }
}
