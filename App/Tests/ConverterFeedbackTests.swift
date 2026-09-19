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
