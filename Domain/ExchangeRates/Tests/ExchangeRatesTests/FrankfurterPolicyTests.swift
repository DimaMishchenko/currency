import Foundation
import Testing

@testable import ExchangeRates

private actor FrankfurterPolicyHTTP: HTTPClient {
  var urls: [URL] = []
  func get(_ url: URL) async throws -> Data {
    urls.append(url)
    return Data(
      #"[{"date":"2026-01-02","base":"EUR","quote":"USD","rate":1.2},{"date":"2026-01-02","base":"EUR","quote":"GBP","rate":0.8}]"#
        .utf8)
  }
}

@Suite struct FrankfurterPolicyTests {
  @Test func everyCurrentRequestSelectsApprovedProvidersAndMarksSterlingParity() async throws {
    let client = FrankfurterPolicyHTTP()
    let quotes = try await FrankfurterProvider(client: client).fetch()
    let url = try #require(await client.urls.first)
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    let providers = try #require(query?.first { $0.name == "providers" }?.value)
    #expect(providers.split(separator: ",").count == 66)
    #expect(providers == FrankfurterProvider.allowedProviders)
    #expect(!providers.split(separator: ",").contains("BOE"))
    for code in ["GGP", "IMP", "JEP"] {
      #expect(quotes[code]?.value == quotes["GBP"]?.value)
      #expect(
        quotes[code]?.source.conversion
          == RateConversion(
            provider: .frankfurter,
            published: "2026-01-02", value: 1, base: "GBP", quote: code))
    }
  }
}
