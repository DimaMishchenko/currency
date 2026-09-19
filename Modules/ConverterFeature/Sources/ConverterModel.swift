import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit

@MainActor @Observable
final class ConverterModel {
  private(set) var input: ConverterState
  var snapshot: RateSnapshot
  var refreshing = false
  var manuallyRefreshing = false
  var warning: LocalizedStringResource?
  private let service: RateService
  let store: CurrencyStore

  init(store: CurrencyStore, service: RateService) {
    self.store = store
    self.service = service
    input = store.input()
    snapshot = store.loadRates()
  }

  private var widgetReload: Task<Void, Never>?
  func reloadInput() { input = store.input() }

  @discardableResult
  func updateInput(_ mutation: (inout ConverterState) -> Void) -> Bool {
    do {
      input = try store.updateInput(mutation)
      widgetReload?.cancel()
      widgetReload = Task {
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        WidgetCenter.shared.reloadAllTimelines()
      }
      return true
    } catch {
      warning = .Converter.selectionSaveFailed
      AppHaptics.play(.error)
      return false
    }
  }

  func refresh(force: Bool = false) async {
    guard !refreshing else { return }
    refreshing = true
    manuallyRefreshing = force
    if force { AppHaptics.play(.action) }
    defer { refreshing = false; manuallyRefreshing = false }
    do {
      let result = try await store.refreshRates(using: service, force: force)
      guard !Task.isCancelled else { return }
      snapshot = result.snapshot
      warning = RateMessages.refresh(result.warning)
      if force { AppHaptics.play(result.warning == nil ? .success : .warning) }
      WidgetCenter.shared.reloadAllTimelines()
    } catch is CancellationError {
      return
    } catch {
      warning = .Converter.rateSaveFailed
      if force && !Task.isCancelled { AppHaptics.play(.error) }
    }
  }
}
