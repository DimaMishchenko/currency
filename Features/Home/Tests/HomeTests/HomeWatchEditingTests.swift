import Conversion
import ExchangeRates
import Foundation
import Testing

@testable import Home

@MainActor
struct HomeWatchEditingTests {
  @Test func textCommitNormalizesDecimalCommaAndRejectsUnsupportedSyntax() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HomeTestStore(directory: directory)
    let model = makeHomeModel(store: store, service: RateService())
    #expect(model.commitAmount(" 0012,50 \n"))
    #expect(model.input.amount == "12.5")
    #expect(store.input() == model.input)
    let confirmed = model.input
    for invalid in ["", "-1", "1e3", "1.2.3", "1,234.50", "USD 10", "١٢٫٥"] {
      #expect(!model.commitAmount(invalid))
      #expect(model.input == confirmed)
      #expect(store.input() == confirmed)
    }
  }

  @Test func failedTextCommitKeepsConfirmedValueAndSupportsRetry() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let store = HomeTestStore(directory: file)
    let model = makeHomeModel(store: store, service: RateService())
    let confirmed = model.input
    #expect(!model.commitAmount("12.50"))
    #expect(model.input == confirmed)
    #expect(model.warning == .selectionSaveFailed)
    try FileManager.default.removeItem(at: file)
    #expect(model.commitAmount("12,50"))
    #expect(model.input.decimal == Decimal(string: "12.5"))
    #expect(store.input() == model.input)
    #expect(model.warning == nil)
  }

  @Test func promotedDestinationPreservesConversionAndOtherSelections() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HomeTestStore(directory: directory)
    try store.updateInput {
      $0.setAmount("12.5")
      $0.setDestinations(["USD", "GBP"])
    }
    let model = makeHomeModel(store: store, service: RateService(), readRates: { self.rates })
    let originalGBP = model.row("GBP").amount
    #expect(model.useAsBase("USD"))
    #expect(model.input.source == "USD")
    #expect(model.input.decimal == 25)
    #expect(model.input.manualDestinations == ["EUR", "GBP"])
    #expect(model.row("GBP").amount == originalGBP)
    #expect(model.row("EUR").amount == Decimal(string: "12.5"))
    #expect(store.input() == model.input)
  }

  @Test func promotionUsesFreshConfirmedAmountAndBase() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HomeTestStore(directory: directory)
    let model = makeHomeModel(store: store, service: RateService(), readRates: { self.rates })
    try store.updateInput {
      $0.changeSource("GBP")
      $0.setAmount("10")
    }
    #expect(model.useAsBase("USD"))
    #expect(model.input.source == "USD")
    #expect(model.input.decimal == 5)
    #expect(store.input() == model.input)
  }

  @Test func missingRatesOrFailedStorageNeverReportPromotionSuccess() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HomeTestStore(directory: directory)
    let unavailable = makeHomeModel(store: store, service: RateService())
    let confirmed = unavailable.input
    #expect(!unavailable.useAsBase("USD"))
    #expect(unavailable.input == confirmed)
    #expect(store.input() == confirmed)
    let file = directory.appendingPathComponent("blocked")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data().write(to: file)
    let rejected = makeHomeModel(
      store: HomeTestStore(directory: file), service: RateService(), readRates: { self.rates })
    let before = rejected.input
    #expect(!rejected.useAsBase("USD"))
    #expect(rejected.input == before)
    #expect(rejected.warning == .selectionSaveFailed)
  }

  private var rates: RateSnapshot {
    RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-10-04", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: "2026-10-04", source: .init(provider: .custom("test"))),
      "GBP": ExchangeRate(4, published: "2026-10-04", source: .init(provider: .custom("test")))
    ])
  }
}
