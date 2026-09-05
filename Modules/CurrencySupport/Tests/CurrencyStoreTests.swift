import CurrencySupport
import ExchangeRates
import Foundation
import Testing

private struct ImmediateProvider: RateProvider {
  let value: Decimal
  func fetch() async throws -> [String: ExchangeRate] {
    ["USD": ExchangeRate(value, published: "2026-01-02", source: .init(provider: .ecb))]
  }
}

private struct FailingProvider: RateProvider {
  func fetch() async throws -> [String: ExchangeRate] {
    throw CocoaError(.fileReadUnknown)
  }
}

private actor SuspendedProvider: RateProvider {
  private var pending: CheckedContinuation<[String: ExchangeRate], Error>?
  private var started: CheckedContinuation<Void, Never>?
  func fetch() async throws -> [String: ExchangeRate] {
    try await withCheckedThrowingContinuation {
      pending = $0
      started?.resume()
      started = nil
    }
  }
  func waitUntilStarted() async {
    if pending != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func fail() {
    pending?.resume(throwing: CocoaError(.fileReadUnknown))
    pending = nil
  }
}

@Suite struct CurrencyStoreTests {
  @Test func interleavedHostsPreserveAmountAndSelectionEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = CurrencyStore(directory: directory)
    let widget = CurrencyStore(directory: directory)
    let displayed = app.input()
    try widget.press("AC")
    try widget.press("4")
    try widget.press("2")
    let updated = try app.updateInput { $0.setDestinations($0.destinations + ["PLN"]) }
    #expect(displayed.amount == "1")
    #expect(updated.amount == "42")
    #expect(widget.input().destinations.contains("PLN"))
    try app.updateInput { $0.moveDestinations(["GBP"], before: "USD") }
    #expect(widget.input().destinations.first == "GBP")
    #expect(widget.input().destinations.contains("PLN"))
  }

  @Test func staleFailedRefreshCannotOverwriteNewerHostCommit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let suspended = SuspendedProvider()
    let service = RateService(fiat: suspended, daily: FailingProvider(), crypto: nil)
    let task = Task {
      try await store.refreshRates(
        using: service, force: true, now: Date(timeIntervalSince1970: 100))
    }
    await suspended.waitUntilStarted()
    let newService = RateService(
      fiat: ImmediateProvider(value: 2), daily: ImmediateProvider(value: 2), crypto: nil)
    _ = try await store.refreshRates(
      using: newService, force: true, now: Date(timeIntervalSince1970: 200))
    await suspended.fail()
    let result = try await task.value
    #expect(result.warning == nil)
    #expect(result.snapshot.quotes["USD"]?.value == 2)
    #expect(store.loadRates().quotes["USD"]?.value == 2)
    #expect(store.loadRates().checkedAt == Date(timeIntervalSince1970: 200))
  }
}
