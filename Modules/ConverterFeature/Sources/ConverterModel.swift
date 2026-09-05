import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit

@MainActor @Observable
final class ConverterModel {
  private(set) var input: ConverterState
  var snapshot: RateSnapshot
  var refreshing = false
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

  func updateInput(_ mutation: (inout ConverterState) -> Void) {
    do {
      input = try store.updateInput(mutation)
      widgetReload?.cancel()
      widgetReload = Task {
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        WidgetCenter.shared.reloadAllTimelines()
      }
    } catch { warning = .Converter.selectionSaveFailed }
  }
  func refresh(force: Bool = false) async {
    guard !refreshing else { return }
    refreshing = true
    defer { refreshing = false }
    do {
      let result = try await store.refreshRates(using: service, force: force)
      snapshot = result.snapshot
      warning = RateMessages.refresh(result.warning)
      WidgetCenter.shared.reloadAllTimelines()
    } catch is CancellationError {
      return
    } catch {
      warning = .Converter.rateSaveFailed
    }
  }
}
