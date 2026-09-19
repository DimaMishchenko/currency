import CurrencySupport
import ExchangeRates
import Foundation
import Testing
import UIKit

@testable import ConverterFeature

private struct SlowFeedbackProvider: RateProvider {
  func fetch() async throws -> [String: ExchangeRate] {
    try await Task.sleep(for: .seconds(30))
    return [:]
  }
}

@MainActor
struct ConverterFeedbackTests {
  @Test func secondaryEditingKeepsBaseAndOrderAndPersistsValue() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let model = ConverterModel(store: store, service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "GBP": ExchangeRate(4, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    let order = model.input.destinations
    let original = model.input
    model.beginEditing("USD")
    #expect(model.input == original)
    #expect(model.press("2"))
    #expect(model.press("5"))
    #expect(model.input.source == "EUR")
    #expect(model.input.destinations == order)
    #expect(model.input.decimal == Decimal(string: "12.5"))
    #expect(store.input() == model.input)
    model.beginEditing("GBP")
    #expect(model.editingText == "50")
    #expect(model.press("."))
    #expect(model.press("1"))
    #expect(model.input.decimal == Decimal(string: "0.025"))
    model.endEditing()
    #expect(model.editor == nil)
    model.beginEditing("EUR")
    #expect(model.press("7"))
    #expect(model.input.amount == "7")
    model.beginEditing("JPY")
    #expect(model.editingCode == "EUR")
    model.reloadInput()
    #expect(model.editor == nil)
  }

  @Test func switchingRowsPreservesRepeatingDecimalConversion() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = ConverterModel(store: CurrencyStore(directory: directory), service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(3, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "GBP": ExchangeRate(6, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    model.beginEditing("USD")
    #expect(model.press("1"))
    #expect(model.input.amount.count > 30)
    model.beginEditing("GBP")
    #expect(model.editingText == "2")
    #expect(model.input.source == "EUR")
  }

  @Test func removingActiveCurrencyClosesEditor() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = ConverterModel(store: CurrencyStore(directory: directory), service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    model.beginEditing("USD")
    #expect(model.editor != nil)
    #expect(model.updateInput { $0.setDestinations($0.destinations.filter { $0 != "USD" }) })
    #expect(model.editor == nil)
    let saved = model.input
    #expect(!model.press("7"))
    #expect(model.input == saved)
  }

  @Test func editingUsesLatestSharedBase() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CurrencyStore(directory: directory)
    let model = ConverterModel(store: store, service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "GBP": ExchangeRate(4, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    model.beginEditing("USD")
    try store.updateInput { $0.changeSource("GBP") }
    #expect(model.press("5"))
    #expect(model.input.source == "GBP")
    #expect(model.input.decimal == 10)
    #expect(store.input() == model.input)
    try store.updateInput { $0.setDestinations($0.destinations.filter { $0 != "USD" }) }
    let saved = store.input()
    #expect(!model.press("7"))
    #expect(store.input() == saved)
  }

  @Test func failedSecondaryEditKeepsDisplayedAndSavedAmounts() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let model = ConverterModel(store: CurrencyStore(directory: file), service: RateService())
    model.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: "2026-09-19", source: .init(provider: .custom("test")))
    ])
    model.beginEditing("USD")
    #expect(model.editor != nil)
    let before = model.editor
    let saved = model.input
    #expect(!model.press("7"))
    #expect(model.editor == before)
    #expect(model.input == saved)
  }

  @Test func nativeRefreshInsetDoesNotInterruptPullPresentation() {
    let coordinator = CurrencyRefreshAttachment.Coordinator()
    let scroll = UIScrollView()
    let attachment = UIView()
    scroll.addSubview(attachment)
    coordinator.attach(from: attachment)
    scroll.contentOffset.y = -90
    coordinator.updatePull()
    #expect(coordinator.state.pulling)
    scroll.contentInset.top = 60
    scroll.contentOffset.y = -90
    coordinator.updatePull()
    #expect(coordinator.state.pulling)
    coordinator.detach()
  }

  @Test func refreshAttachmentRecoversAfterScrollViewReconfiguration() {
    let coordinator = CurrencyRefreshAttachment.Coordinator()
    let scroll = UIScrollView()
    let attachment = UIView()
    scroll.addSubview(attachment)
    coordinator.attach(from: attachment)
    #expect(scroll.refreshControl === coordinator.control)
    scroll.refreshControl = nil
    coordinator.attach(from: attachment)
    #expect(scroll.refreshControl === coordinator.control)
    coordinator.start()
    coordinator.detach()
    #expect(scroll.refreshControl == nil)
    #expect(coordinator.state.started == nil)
  }

  @Test func disabledRefreshCanResumeWhenSceneReactivates() {
    let coordinator = CurrencyRefreshAttachment.Coordinator()
    coordinator.sync(refreshing: true)
    #expect(coordinator.state.started != nil)
    coordinator.enabled = false
    coordinator.sync(refreshing: true)
    #expect(coordinator.state.started == nil)
    coordinator.enabled = true
    coordinator.sync(refreshing: true)
    #expect(coordinator.state.started != nil)
    coordinator.detach()
  }

  @Test func cancelledManualRefreshClearsIndicatorWithoutError() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = ConverterModel(
      store: CurrencyStore(directory: directory),
      service: RateService(fiat: SlowFeedbackProvider(), daily: SlowFeedbackProvider(), crypto: nil)
    )
    let task = Task { await model.refresh(force: true) }
    for _ in 0..<100 where !model.refreshing { await Task.yield() }
    #expect(model.manuallyRefreshing)
    task.cancel()
    await task.value
    #expect(!model.refreshing)
    #expect(!model.manuallyRefreshing)
    #expect(model.warning == nil)
  }

  @Test func failedInputSaveDoesNotReportSuccessfulMutation() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let model = ConverterModel(store: CurrencyStore(directory: file), service: RateService())
    let original = model.input
    #expect(!model.updateInput { $0.press("7") })
    #expect(model.input == original)
    #expect(model.warning != nil)
  }
}
