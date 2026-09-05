import Foundation

/// A provider backed by the Fawaz daily currency feed.
public struct FawazProvider: RateProvider {
  let client: any HTTPClient
  /// Creates a Fawaz provider.
  public init(client: any HTTPClient = NetworkClient()) { self.client = client }
  /// Fetches daily quotes using the configured CDN fallbacks.
  public func fetch() async throws -> [String: ExchangeRate] {
    for endpoint in [
      "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/eur.min.json",
      "https://latest.currency-api.pages.dev/v1/currencies/eur.min.json"
    ] {
      guard let url = URL(string: endpoint) else { throw RateError.invalidData }
      do { return try Self.decode(await client.get(url)) } catch {
        try Task.checkCancellation()
      }
    }
    throw RateError.unavailable
  }
  /// Decodes a Fawaz payload into normalized quotes.
  static func decode(_ data: Data) throws -> [String: ExchangeRate] {
    struct Payload: Decodable {
      let date: String
      let eur: [String: Decimal]
    }
    let payload = try JSONDecoder().decode(Payload.self, from: data)
    guard validDate(payload.date), payload.eur["usd"] != nil, payload.eur["btc"] != nil else {
      throw RateError.invalidData
    }
    var result: [String: ExchangeRate] = [:]
    for (code, value) in payload.eur where CurrencyCatalog.codes.contains(code.uppercased()) {
      guard value > 0, !value.isNaN else { throw RateError.invalidData }
      result[code.uppercased()] = ExchangeRate(
        value, published: payload.date, source: .init(provider: .fawaz, observation: .dailyRate))
    }
    result["EUR"] = ExchangeRate(
      1, published: payload.date, source: .init(provider: .fawaz, observation: .dailyRate))
    return result
  }
}
