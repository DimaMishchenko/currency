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
  private(set) var editor: WidgetInput?
  private(set) var editingSelectionID: String?
  var editingCode: String { editor?.active ?? input.source }
  var editingText: String { editor?.amount ?? input.amount }

  func reloadInput(preservingEditor: Bool = false) {
    let next = store.input()
    if !preservingEditor || next.source != input.source || next.amount != input.amount
      || (editor.map { !canEdit($0.active, selectionID: editingSelectionID, in: next) } ?? false)
    {
      editor = nil
    }
    input = next
  }

  func beginEditing(_ code: String, selectionID: String? = nil) {
    let id = selectionID ?? code
    guard canEdit(code, selectionID: id, in: input),
      snapshot.convert(input.decimal, from: input.source, to: code) != nil
    else { return }
    var next = WidgetInput(codes: [input.source] + input.destinations)
    next.preset(input.decimal)
    next.select(code, snapshot: snapshot)
    var value = next.decimal
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, CurrencyDisplay.fractionDigits(code), .plain)
    next.preset(rounded)
    editor = next
    editingSelectionID = id
  }

  private func canEdit(_ code: String, selectionID: String?, in state: ConverterState) -> Bool {
    if selectionID == state.source { return code == state.source }
    return state.destinationRows.contains { $0.id == selectionID && $0.code == code }
  }

  func endEditing() { editor = nil }

  @discardableResult
  func press(_ key: String) -> Bool {
    guard var next = editor else { return false }
    next.press(key)
    guard
      updateInput({
        guard canEdit(next.active, selectionID: editingSelectionID, in: $0),
          let value = snapshot.convert(next.decimal, from: next.active, to: $0.source)
        else { throw EditingError.unavailableCurrency }
        if next.active == $0.source {
          $0.setAmount(next.amount)
        } else {
          $0.setConvertedAmount(value)
        }
      })
    else { return false }
    editor = next
    return true
  }

  private enum EditingError: Error { case unavailableCurrency }

  @discardableResult
  func updateInput(_ mutation: (inout ConverterState) throws -> Void) -> Bool {
    do {
      input = try store.updateInput(mutation)
      if let editor, !canEdit(editor.active, selectionID: editingSelectionID, in: input) {
        self.editor = nil
      }
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
