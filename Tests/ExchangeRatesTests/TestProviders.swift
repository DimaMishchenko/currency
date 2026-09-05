import ExchangeRates

struct StubRateProvider: RateProvider {
  let quotes: [String: ExchangeRate]?
  func fetch() async throws -> [String: ExchangeRate] {
    guard let quotes else { throw RateError.unavailable }
    return quotes
  }
}
