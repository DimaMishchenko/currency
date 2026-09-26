import Conversion
import CurrencyApplication
import ExchangeRates
import Foundation
import LocalCurrency
import Testing

@Suite struct ConversionActionTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  @Test func missingRatesInsideThrottleNeverForceRefresh() async throws {
    let action = make(snapshot: .init(checkedAt: now)) { _ in
      Issue.record("Unexpected refresh"); return .init(snapshot: .init(), warning: nil)
    }
    let request = try action.request(amount: "10", source: "EUR", destination: "USD")
    let result = try await action.perform(request)
    #expect(result.results[0].availability == .missingRates)
  }
  @Test func identitySkipsNetworkEvenWithoutCache() async throws {
    let action = make(snapshot: .init()) { _ in
      Issue.record("Unexpected refresh"); return .init(snapshot: .init(), warning: nil)
    }
    let result = try await action.perform(
      action.request(amount: "10", source: "EUR", destination: "EUR"))
    #expect(result.results[0].amount == "10")
  }
  @Test func myCurrenciesUsesDestinationsAndPreservesUnavailableLocal() throws {
    var input = ConverterState()
    input.changeSource("GBP"); input.setDestinations(["USD", "CZK"]); input.setAmount("42")
    input.setUsesLocalCurrency(true)
    let confirmed = input
    let action = ConversionAction(
      dependencies: .init(
        readInput: { confirmed }, readLocal: { (nil, .denied) }, readRates: { .init() },
        refresh: { _ in .init(snapshot: .init(), warning: nil) }, now: { now }))
    let request = try action.request(amount: "15", source: "EUR")
    #expect(request.source == "EUR" && request.amount == "15")
    #expect(request.destinations.map(\.id) == ["USD", "CZK", "@local"])
    #expect(request.destinations.last?.code == nil)
    #expect(action.dependencies.readInput() == confirmed)
  }
  @Test func dueRefreshUsesTypedWarningAndCancellationIsNotFallback() async throws {
    let snapshot = RateSnapshot(
      quotes: [
        "EUR": .init(1, published: "2027-01-15", source: .init(provider: .ecb)),
        "USD": .init(2, published: "2027-01-15", source: .init(provider: .ecb))
      ], fetchedAt: now)
    let action = make(snapshot: .init()) { _ in
      .init(snapshot: snapshot, warning: .partialCryptoFallback)
    }
    let request = try action.request(amount: "10", source: "EUR", destination: "USD")
    let result = try await action.perform(request)
    #expect(result.results[0].amount == "20" && !result.refreshFailed)
    let cancelled = make(snapshot: .init()) { _ in throw CancellationError() }
    await #expect(throws: CancellationError.self) { try await cancelled.perform(request) }
  }
  @Test func refreshFailureReturnsUsableCacheWithDisclosure() async throws {
    let snapshot = RateSnapshot(
      quotes: [
        "EUR": .init(1, published: "2027-01-15", source: .init(provider: .ecb)),
        "USD": .init(2, published: "2027-01-15", source: .init(provider: .ecb))
      ], fetchedAt: now.addingTimeInterval(-3600))
    let action = make(snapshot: snapshot) { _ in throw CocoaError(.fileWriteNoPermission) }
    let result = try await action.perform(
      action.request(amount: "10", source: "EUR", destination: "USD"))
    #expect(result.results[0].amount == "20" && result.refreshFailed && result.cacheIsStale)
  }
  private func make(
    snapshot: RateSnapshot, refresh: @escaping @Sendable (Date) async throws -> RefreshResult
  ) -> ConversionAction {
    ConversionAction(
      dependencies: .init(
        readInput: { .init() }, readLocal: { (nil, .notDetermined) }, readRates: { snapshot },
        refresh: refresh, now: { now }))
  }
}
