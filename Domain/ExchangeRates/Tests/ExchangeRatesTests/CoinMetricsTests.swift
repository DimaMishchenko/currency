import Foundation
import Testing

@testable import ExchangeRates

private actor MetricsHTTP: HTTPClient {
  var responses: [Result<Data, RateError>]
  private(set) var urls: [URL] = []
  private(set) var starts: [ContinuousClock.Instant] = []
  init(_ responses: [Result<Data, RateError>]) { self.responses = responses }
  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    starts.append(ContinuousClock().now)
    guard !responses.isEmpty else { throw RateError.unavailable }
    return try responses.removeFirst().get()
  }
}

private let metricsNow = Date(timeIntervalSince1970: 1_767_355_200)

private func metricsPage(_ rows: [[String: Any]], next: String? = nil) throws -> Data {
  var object: [String: Any] = ["data": rows]
  if let next { object["next_page_url"] = next }
  return try JSONSerialization.data(withJSONObject: object)
}

private func metricsRow(_ asset: String, _ value: String, age: TimeInterval = 60) -> [String: Any] {
  [
    "asset": asset, "ReferenceRateUSD": value,
    "time": metricsNow.addingTimeInterval(-age).ISO8601Format()
  ]
}

private func metricsClient(_ http: MetricsHTTP) -> CoinMetricsClient {
  CoinMetricsClient(client: http, acquire: {}, sleep: { _ in })
}

@Suite struct CoinMetricsTests {
  @Test func communityNanosecondTimestampDecodesWithoutInventingPrecision() throws {
    let parsed = try #require(CoinMetricsClient.date("2026-01-02T11:59:00.000000000Z"))
    #expect(parsed == metricsNow.addingTimeInterval(-60))
  }

  @Test func pagingKeepsOnlyValidRequestedObservationsAndSortsUniqueTimes() async throws {
    let next =
      "https://community-api.coinmetrics.io/v4/timeseries/asset-metrics?next_page_token=opaque"
    let http = MetricsHTTP([
      .success(
        try metricsPage(
          [
            metricsRow("btc", "10"), metricsRow("btc", "0"), metricsRow("eth", "100"),
            metricsRow("btc", "NaN"), metricsRow("btc", "11", age: -60),
            metricsRow("btc", "20", age: 900),
            ["asset": "btc", "time": "bad", "ReferenceRateUSD": 1]
          ], next: next)),
      .success(try metricsPage([metricsRow("btc", "12", age: 120), metricsRow("btc", "10")]))
    ])
    let points = try await metricsClient(http)
      .observations(
        assets: ["BTC"], start: metricsNow.addingTimeInterval(-600), end: metricsNow)
    #expect(points.keys.sorted() == ["BTC"])
    #expect(points["BTC"]?.map(\.value) == [12, 10])
    #expect(await http.urls.count == 2)
    #expect(await http.urls.last?.absoluteString == next)
  }

  @Test(arguments: [
    "https://evil.example/v4/timeseries/asset-metrics",
    "http://community-api.coinmetrics.io/v4/timeseries/asset-metrics",
    "https://community-api.coinmetrics.io/v4/catalog/assets",
    "https://user@community-api.coinmetrics.io/v4/timeseries/asset-metrics"
  ]) func unsafePaginationIsRejectedBeforeRequest(_ next: String) async throws {
    let http = MetricsHTTP([.success(try metricsPage([], next: next))])
    await #expect(throws: RateError.self) {
      try await metricsClient(http)
        .observations(
          assets: ["btc"], start: metricsNow.addingTimeInterval(-600), end: metricsNow)
    }
    #expect(await http.urls.count == 1)
  }

  @Test func repeatedPaginationCannotLoop() async throws {
    let next =
      "https://community-api.coinmetrics.io/v4/timeseries/asset-metrics?next_page_token=same"
    let page = try metricsPage([], next: next)
    let http = MetricsHTTP([.success(page), .success(page)])
    await #expect(throws: RateError.self) {
      try await metricsClient(http)
        .observations(
          assets: ["btc"], start: metricsNow.addingTimeInterval(-600), end: metricsNow)
    }
    #expect(await http.urls.count == 2)
  }

  @Test func rateLimitRetriesAreBoundedAndCancellationPropagates() async throws {
    let http = MetricsHTTP([.failure(.http(429)), .failure(.http(429)), .failure(.http(429))])
    await #expect(throws: RateError.self) {
      try await metricsClient(http)
        .observations(
          assets: ["btc"], start: metricsNow.addingTimeInterval(-600), end: metricsNow)
    }
    #expect(await http.urls.count == 3)
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await metricsClient(http)
        .observations(
          assets: ["btc"], start: metricsNow.addingTimeInterval(-600), end: metricsNow)
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(await http.urls.count == 3)
  }

  @Test func separateClientsShareCommunityRequestPacing() async throws {
    let page = try metricsPage([metricsRow("btc", "100")])
    let http = MetricsHTTP([.success(page), .success(page), .success(page)])
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<3 {
        group.addTask {
          _ = try await CoinMetricsClient(client: http)
            .observations(
              assets: ["btc"], start: metricsNow.addingTimeInterval(-600), end: metricsNow)
        }
      }
      try await group.waitForAll()
    }
    let starts = await http.starts.sorted()
    #expect(starts.count == 3)
    for (first, second) in zip(starts, starts.dropFirst()) {
      #expect(first.duration(to: second) >= .milliseconds(640))
    }
  }

  @Test func malformedEnvelopeIsRejected() async {
    let http = MetricsHTTP([.success(Data(#"{"error":"unavailable"}"#.utf8))])
    await #expect(throws: (any Error).self) {
      try await metricsClient(http)
        .observations(
          assets: ["btc"], start: metricsNow.addingTimeInterval(-600), end: metricsNow)
    }
  }

  @Test func currentQuotesPreserveObservationAndDailyConversionProvenance() async throws {
    let http = MetricsHTTP([.success(try metricsPage([metricsRow("btc", "50000")]))])
    let daily = StubRateProvider(quotes: [
      "USD": ExchangeRate(2, published: "2026-01-02", source: .init(provider: .fawaz))
    ])
    let quotes = try await CoinMetricsProvider(
      metrics: metricsClient(http), daily: daily, now: { metricsNow }
    )
    .fetch()
    let btc = try #require(quotes["BTC"])
    #expect(btc.value == Decimal(string: "0.00004"))
    #expect(btc.observedAt == metricsNow.addingTimeInterval(-60))
    #expect(btc.retrievedAt == metricsNow)
    #expect(btc.source.provider == .coinMetrics)
    #expect(btc.source.observation == .minuteReference)
    #expect(btc.source.conversion?.provider == .fawaz)
    #expect(btc.source.conversion?.value == 2)
    #expect(btc.source.conversion?.published == "2026-01-02")
  }

  @Test(arguments: ["2025-12-20", "2026-01-03"])
  func staleOrFutureFXCannotCreateCurrentQuote(_ day: String) async throws {
    let http = MetricsHTTP([.success(try metricsPage([metricsRow("btc", "50000")]))])
    await #expect(throws: RateError.self) {
      try await CoinMetricsProvider(
        metrics: metricsClient(http),
        daily: StubRateProvider(quotes: [
          "USD": ExchangeRate(2, published: day, source: .init(provider: .fawaz))
        ]), now: { metricsNow }
      )
      .fetch()
    }
  }

  @Test func staleAndFutureMinuteDataCannotCreateCurrentQuote() async throws {
    let http = MetricsHTTP([
      .success(
        try metricsPage([
          metricsRow("btc", "50000", age: 601), metricsRow("btc", "50000", age: -1)
        ]))
    ])
    await #expect(throws: RateError.self) {
      try await CoinMetricsProvider(
        metrics: metricsClient(http),
        daily: StubRateProvider(quotes: [
          "USD": ExchangeRate(2, published: "2026-01-02", source: .init(provider: .fawaz))
        ]), now: { metricsNow }
      )
      .fetch()
    }
  }

  @Test func oldProviderCacheDecodesButCannotReenterEitherPolicy() throws {
    let source = try JSONDecoder()
      .decode(
        RateSource.self,
        from: Data(#"{"provider":{"coinbase":{}},"observation":"exchangeRate"}"#.utf8))
    #expect(source.provider == .custom("Coinbase"))
    let saved = RateSnapshot(
      quotes: [
        "BTC": ExchangeRate(1, published: "2026-01-02", source: source, retrievedAt: metricsNow)
      ], fetchedAt: metricsNow)
    for policy in [RateProviderPolicy.daily, .intradayEnhanced] {
      #expect(policy.filter(saved).quotes.isEmpty)
      #expect(policy.filter(saved).checkedAt == nil)
    }
  }
}
