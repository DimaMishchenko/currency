import Foundation

/// A provider for Coinbase's current cryptocurrency exchange rates.
public struct CoinbaseProvider: RateProvider {
  let client: any HTTPClient
  /// Creates a Coinbase provider.
  public init(client: any HTTPClient = NetworkClient()) { self.client = client }
  /// Fetches all supported cryptocurrency rates in a single unauthenticated request.
  public func fetch() async throws -> [String: ExchangeRate] {
    guard let url = URL(string: "https://api.coinbase.com/v2/exchange-rates?currency=EUR") else {
      throw RateError.invalidData
    }
    let data = try await client.get(url)
    try Task.checkCancellation()
    return try Self.decode(data)
  }

  /// Validates EUR normalization and skips individual missing or malformed quotes.
  /// Coinbase supplies no market observation timestamp; `now` records retrieval only.
  static func decode(_ data: Data, now: Date = .now) throws -> [String: ExchangeRate] {
    struct Payload: Decodable {
      struct Rates: Decodable {
        let currency: String
        let rates: [String: String]
      }

      let data: Rates
    }
    let payload = try JSONDecoder().decode(Payload.self, from: data).data
    guard payload.currency == "EUR", decimal(payload.rates["EUR"]) == 1 else {
      throw RateError.invalidData
    }
    var result: [String: ExchangeRate] = [:]
    for code in CurrencyCatalog.crypto {
      guard let value = decimal(payload.rates[code]) else { continue }
      // Already coins per EUR; no inversion or intermediate fiat conversion is needed.
      result[code] = ExchangeRate(
        value, published: String(now.ISO8601Format().prefix(10)),
        source: .init(provider: .coinbase, observation: .exchangeRate), retrievedAt: now)
    }
    guard !result.isEmpty else { throw RateError.invalidData }
    return result
  }

  private static func decimal(_ raw: String?) -> Decimal? {
    guard let raw,
      raw.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression)
        == raw.startIndex..<raw.endIndex,
      let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
      value > 0, !value.isNaN
    else { return nil }
    return value
  }

}
