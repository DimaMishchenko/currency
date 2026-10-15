import Foundation

/// Keyless Community reference-rate observations, expressed in USD per asset.
public struct CoinMetricsClient: Sendable {
  private let client: any HTTPClient
  private let acquire: @Sendable () async throws -> Void
  private let sleep: @Sendable (Duration) async throws -> Void

  public init(client: any HTTPClient = NetworkClient()) {
    self.client = client
    self.acquire = { try await CoinMetricsPacer.shared.acquire() }
    self.sleep = { try await Task.sleep(for: $0) }
  }

  init(
    client: any HTTPClient, acquire: @escaping @Sendable () async throws -> Void,
    sleep: @escaping @Sendable (Duration) async throws -> Void
  ) {
    self.client = client
    self.acquire = acquire
    self.sleep = sleep
  }

  /// Returns ascending, unique observations within the inclusive requested time range.
  public func observations(
    assets: [String], start: Date, end: Date, frequency: String = "1m"
  ) async throws -> [String: [HistoryPoint]] {
    let assets = Set(assets.map { $0.lowercased() })
    guard !assets.isEmpty,
      assets.allSatisfy({
        $0.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil
      }), start <= end, ["1m", "1h", "1d"].contains(frequency)
    else {
      throw RateError.invalidData
    }
    var components = URLComponents(
      string: "https://community-api.coinmetrics.io/v4/timeseries/asset-metrics")!
    components.queryItems = [
      .init(name: "assets", value: assets.sorted().joined(separator: ",")),
      .init(name: "metrics", value: "ReferenceRateUSD"),
      .init(name: "frequency", value: frequency),
      .init(name: "start_time", value: start.ISO8601Format()),
      .init(name: "end_time", value: end.ISO8601Format()),
      .init(name: "page_size", value: "10000")
    ]
    var next = components.url
    var visited: Set<URL> = []
    var points: [String: [Date: Double]] = [:]
    while let url = next {
      try Task.checkCancellation()
      guard Self.safe(url), visited.count < 100, visited.insert(url).inserted else {
        throw RateError.invalidData
      }
      let page = try JSONDecoder().decode(Page.self, from: await load(url))
      for row in page.data {
        guard let asset = row.asset?.lowercased(), assets.contains(asset),
          let rawTime = row.time, let date = Self.date(rawTime), date >= start, date <= end,
          let raw = row.rate,
          raw.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
          let value = Double(raw), value.isFinite, value > 0
        else { continue }
        points[asset.uppercased(), default: [:]][date] = value
      }
      if let raw = page.nextPageURL, !raw.isEmpty {
        guard let candidate = URL(string: raw), Self.safe(candidate) else {
          throw RateError.invalidData
        }
        next = candidate
      } else {
        next = nil
      }
    }
    return points.mapValues { values in
      values.map { HistoryPoint(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
    }
  }

  private func load(_ url: URL) async throws -> Data {
    for attempt in 0..<3 {
      try Task.checkCancellation()
      try await acquire()
      do {
        let data = try await client.get(url)
        try Task.checkCancellation()
        return data
      } catch RateError.http(429) {
        guard attempt < 2 else { throw RateError.http(429) }
        try await sleep(.seconds(6))
      }
    }
    throw RateError.unavailable
  }

  private static func safe(_ url: URL) -> Bool {
    url.scheme == "https" && url.host == "community-api.coinmetrics.io"
      && url.path == "/v4/timeseries/asset-metrics" && url.port == nil
      && url.user == nil && url.password == nil && url.fragment == nil
  }

  static func date(_ raw: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
  }

  private struct Page: Decodable {
    let data: [Row]
    let nextPageURL: String?
    enum CodingKeys: String, CodingKey { case data; case nextPageURL = "next_page_url" }
  }

  private struct Row: Decodable {
    let asset: String?
    let time: String?
    let rate: String?
    enum CodingKeys: String, CodingKey { case asset, time; case rate = "ReferenceRateUSD" }
    init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      asset = try? values.decode(String.self, forKey: .asset)
      time = try? values.decode(String.self, forKey: .time)
      rate = try? values.decode(String.self, forKey: .rate)
    }
  }
}

private actor CoinMetricsPacer {
  static let shared = CoinMetricsPacer()
  private let clock = ContinuousClock()
  private var lastStart: ContinuousClock.Instant?

  func acquire() async throws {
    while let lastStart, clock.now < lastStart.advanced(by: .milliseconds(650)) {
      try await clock.sleep(until: lastStart.advanced(by: .milliseconds(650)))
    }
    try Task.checkCancellation()
    lastStart = clock.now
  }
}
