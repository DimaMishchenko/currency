import Foundation

struct FrankfurterRow: Decodable {
  let date: String
  let base: String
  let quote: String
  let rate: Decimal
}
/// A provider backed by the Frankfurter reference-rate API.
public struct FrankfurterProvider: RateProvider {
  let client: any HTTPClient
  /// Creates a Frankfurter provider.
  public init(client: any HTTPClient = NetworkClient()) { self.client = client }
  /// Fetches current Frankfurter reference rates.
  public func fetch() async throws -> [String: ExchangeRate] {
    guard let url = URL(string: "https://api.frankfurter.dev/v2/rates?base=EUR") else {
      throw RateError.invalidData
    }
    return try Self.decode(await client.get(url))
  }
  /// Decodes Frankfurter rows into normalized quotes.
  static func decode(_ data: Data) throws -> [String: ExchangeRate] {
    let rows = try JSONDecoder().decode([FrankfurterRow].self, from: data)
    guard !rows.isEmpty else { throw RateError.invalidData }
    var result: [String: ExchangeRate] = [:]
    for row in rows {
      guard row.base == "EUR", validDate(row.date), row.rate > 0, !row.rate.isNaN else {
        throw RateError.invalidData
      }
      guard CurrencyCatalog.codes.contains(row.quote), !CurrencyCatalog.crypto.contains(row.quote)
      else {
        continue
      }
      if row.date >= (result[row.quote]?.published ?? "") {
        result[row.quote] = ExchangeRate(
          row.rate, published: row.date,
          source: .init(provider: .frankfurter, observation: .dailyRate))
      }
    }
    guard let day = result["USD"]?.published else { throw RateError.invalidData }
    result["EUR"] = ExchangeRate(
      1, published: day, source: .init(provider: .frankfurter, observation: .dailyRate))
    return result
  }
}
