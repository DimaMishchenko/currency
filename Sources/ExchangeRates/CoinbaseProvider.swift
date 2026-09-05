import Foundation

/// A provider for recent Coinbase cryptocurrency quotes.
public struct CoinbaseProvider: RateProvider {
  let client: any HTTPClient
  /// Creates a Coinbase provider.
  public init(client: any HTTPClient = NetworkClient()) { self.client = client }
  /// Fetches recent quotes for supported cryptocurrencies.
  public func fetch() async throws -> [String: ExchangeRate] {
    var result: [String: ExchangeRate] = [:]
    for code in CurrencyCatalog.crypto.sorted() {
      do {
        guard
          let url = URL(
            string: "https://api.exchange.coinbase.com/products/\(code)-EUR/ticker")
        else { throw RateError.invalidData }
        let data = try await client.get(url)
        result[code] = try Self.decode(data)
      } catch { try Task.checkCancellation() }
      // Public limit is 10 requests/second per IP. Pace even fast cached replies.
      try await Task.sleep(for: .milliseconds(150))
    }
    guard !result.isEmpty else { throw RateError.unavailable }
    return result
  }
  /// Decodes and validates a Coinbase ticker.
  static func decode(_ data: Data, now: Date = .now) throws -> ExchangeRate {
    struct Ticker: Decodable {
      let price: String
      let time: String
    }
    let ticker = try JSONDecoder().decode(Ticker.self, from: data)
    let parser = ISO8601DateFormatter()

    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fractional = parser.date(from: ticker.time)
    parser.formatOptions = [.withInternetDateTime]
    guard let time = fractional ?? parser.date(from: ticker.time),
      now.timeIntervalSince(time) >= -60, now.timeIntervalSince(time) < 3600,
      let price = Decimal(string: ticker.price, locale: Locale(identifier: "en_US_POSIX")),
      price > 0, !price.isNaN
    else { throw RateError.invalidData }
    // Ticker is EUR per coin; RateSnapshot stores coins per EUR.
    return ExchangeRate(
      1 / price, published: String(ticker.time.prefix(10)),
      source: .init(provider: .coinbase, observation: .trade), observedAt: time)
  }
}
