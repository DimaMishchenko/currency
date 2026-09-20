import Conversion
import ExchangeRates
import Foundation
import LocalCurrency
import Observation

/// Owns workspace editing and manual refresh without presentation or persistence policy.
@MainActor @Observable
public final class HomeModel {
  /// Latest confirmed converter input.
  public private(set) var input: ConverterState
  /// Rates used for current rendering and editing.
  public var snapshot: RateSnapshot
  /// Whether a manual refresh currently owns the model.
  public var refreshing = false
  /// Whether the owned refresh was explicitly forced.
  public var manuallyRefreshing = false
  /// Typed issue from a failed edit or refresh.
  public var warning: HomeIssue?
  @ObservationIgnored private let dependencies: HomeDependencies
  @ObservationIgnored private var refreshIdentity: UUID?

  /// Restores current input and rates without starting background work.
  public init(dependencies: HomeDependencies) {
    self.dependencies = dependencies
    input = dependencies.readInput()
    snapshot = dependencies.readRates()
    warning = dependencies.readRateIssue()
  }

  /// Temporary amount editing state; confirmed input remains separately persisted.
  public private(set) var editor: AmountEditor?
  /// Stable identity of the row receiving input.
  public private(set) var editingSelectionID: String?
  /// Resolved currency receiving keypad input.
  public var editingCode: String { editor?.active ?? input.source }
  /// Ungrouped decimal text currently shown for editing.
  public var editingText: String { editor?.amount ?? input.amount }

  /// Reconciles externally edited input, preserving a valid unchanged editor when requested.
  public func reloadInput(preservingEditor: Bool = false) {
    let next = dependencies.readInput()
    if !preservingEditor || next.source != input.source || next.amount != input.amount
      || (editor.map { !canEdit($0.active, selectionID: editingSelectionID, in: next) } ?? false)
    {
      editor = nil
    }
    input = next
  }

  /// Reconciles input and rates after an authoritative shared-state notification.
  public func reloadSharedState() {
    reloadInput(preservingEditor: true)
    snapshot = dependencies.readRates()
    // A background rate or input notification must not hide a failed selection commit.
    if warning != .selectionSaveFailed { warning = dependencies.readRateIssue() }
  }

  /// Observes the same capabilities captured at this model's flow entry.
  public func observeChanges() async {
    reloadSharedState()
    for await _ in dependencies.changes() {
      guard !Task.isCancelled else { return }
      reloadSharedState()
    }
  }

  /// Starts editing a convertible selected row without changing its position.
  public func beginEditing(_ code: String, selectionID: String? = nil) {
    let id = selectionID ?? code
    guard canEdit(code, selectionID: id, in: input),
      snapshot.convert(input.decimal, from: input.source, to: code) != nil
    else { return }
    var next = AmountEditor(codes: [input.source] + input.destinations)
    next.preset(input.decimal)
    next.select(code, snapshot: snapshot)
    var value = next.decimal
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, CurrencyPrecision.fractionDigits(code), .plain)
    next.preset(rounded)
    editor = next
    editingSelectionID = id
  }

  private func canEdit(_ code: String, selectionID: String?, in state: ConverterState) -> Bool {
    if selectionID == state.source { return code == state.source }
    return state.destinationRows.contains { $0.id == selectionID && $0.code == code }
  }

  /// Ends temporary keypad input.
  public func endEditing() { editor = nil }

  /// Commits one keypad action against freshly read input.
  @discardableResult
  public func press(_ key: String) -> Bool {
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

  /// Commits a selection mutation and keeps the last valid state on failure.
  @discardableResult
  public func updateInput(_ mutation: (inout ConverterState) throws -> Void) -> Bool {
    do {
      input = try dependencies.editInput(mutation)
      if let editor, !canEdit(editor.active, selectionID: editingSelectionID, in: input) {
        self.editor = nil
      }
      return true
    } catch {
      warning = .selectionSaveFailed
      return false
    }
  }

  /// Ignores repeated actions and rejects cancelled or superseded operation results.
  @discardableResult
  public func refresh(force: Bool = false) async -> HomeRefreshOutcome {
    guard !Task.isCancelled else { return .cancelled }
    guard !refreshing else { return .ignored }
    let identity = UUID()
    refreshIdentity = identity
    refreshing = true
    manuallyRefreshing = force
    defer { finishRefresh(identity) }
    do {
      let result = try await withTaskCancellationHandler {
        try await dependencies.refreshRates(force)
      } onCancel: {
        Task { @MainActor [weak self] in self?.finishRefresh(identity) }
      }
      guard !Task.isCancelled, refreshIdentity == identity else { return .cancelled }
      snapshot = result.snapshot
      warning = result.warning.map(HomeIssue.rateWarning)
      return result.warning == nil ? .refreshed : .warning
    } catch is CancellationError {
      return .cancelled
    } catch {
      guard !Task.isCancelled, refreshIdentity == identity else { return .cancelled }
      warning = .rateSaveFailed
      return .failed
    }
  }

  private func finishRefresh(_ identity: UUID) {
    guard refreshIdentity == identity else { return }
    refreshIdentity = nil
    refreshing = false
    manuallyRefreshing = false
  }

  /// Fresh authorized local currency, suitable for selecting the dynamic Local row.
  public var availableLocalCurrency: String? {
    let (location, status) = dependencies.readLocalCurrency()
    return status == .available && location?.isFresh() == true ? location?.currency : nil
  }

}
