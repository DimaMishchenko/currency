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
  public private(set) var snapshot: RateSnapshot
  /// Whether a manual refresh currently owns the model.
  public private(set) var refreshing = false
  /// Whether the owned refresh was explicitly forced.
  public private(set) var manuallyRefreshing = false
  /// Typed issue from a failed edit or refresh.
  public private(set) var warning: HomeIssue?
  @ObservationIgnored private let dependencies: HomeDependencies
  @ObservationIgnored private var refreshIdentity: UUID?
  /// Tip currently offered to the UI for native presentation.
  public private(set) var activeDiscoveryTip: HomeDiscoveryTip?
  /// Whether the history tip appeared during this foreground visit.
  public private(set) var historyTipShownThisVisit = false
  @ObservationIgnored private var firstVisitAfterOnboarding: Bool
  @ObservationIgnored private var discoveryVisitID: UUID?
  @ObservationIgnored private var skipWidgetsThisVisit = false
  @ObservationIgnored private var editStartingAmount: Decimal?
  @ObservationIgnored private var closedWithResults = false

  /// Restores current input and rates without starting background work.
  public init(dependencies: HomeDependencies) {
    self.dependencies = dependencies
    input = dependencies.readInput()
    snapshot = dependencies.readRates()
    warning = dependencies.readRateIssue()
    firstVisitAfterOnboarding = !dependencies.onboardingCompleted()
  }

  /// Temporary amount editing state; confirmed input remains separately persisted.
  public private(set) var editor: AmountEditor?
  /// Stable identity of the row receiving input.
  public private(set) var editingSelectionID: String?
  /// Resolved currency receiving keypad input.
  public var editingCode: String { editor?.active ?? input.source }
  /// Ungrouped decimal text currently shown for editing.
  public var editingText: String { editor?.amount ?? input.amount }

  /// Projects the current amount and editing policy for a fixed or dynamic selection.
  public func row(_ code: String, selectionID: String? = nil) -> HomeCurrencyRow {
    let amount = snapshot.convert(input.decimal, from: input.source, to: code)
    return HomeCurrencyRow(
      amount: amount,
      isEditable: amount != nil && canEdit(code, selectionID: selectionID ?? code, in: input))
  }

  /// Reconciles externally edited input, preserving a valid unchanged editor when requested.
  public func reloadInput(preservingEditor: Bool = false) {
    let next = dependencies.readInput()
    if !preservingEditor || next.source != input.source || next.amount != input.amount
      || (editor.map { !canEdit($0.active, selectionID: editingSelectionID, in: next) } ?? false)
    {
      editor = nil
    }
    input = next
    if editor == nil { editStartingAmount = nil }
  }

  /// Reconciles input and rates after an authoritative shared-state notification.
  public func reloadSharedState() {
    snapshot = dependencies.readRates()
    reloadInput(preservingEditor: true)
    reconcileEditor()
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
    guard row(code, selectionID: id).isEditable else { return }
    if editor != nil { recordCompletedEdit() }
    var next = AmountEditor(codes: [input.source] + input.destinations)
    next.preset(input.decimal)
    next.select(code, snapshot: snapshot)
    var value = next.decimal
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, CurrencyPrecision.fractionDigits(code), .plain)
    next.preset(rounded)
    editor = next
    editingSelectionID = id
    editStartingAmount = input.decimal
    closedWithResults = false
    if activeDiscoveryTip == .widgets { activeDiscoveryTip = nil }
  }

  /// Starts a foreground visit and anchors later-day discovery.
  public func beginDiscoveryVisit(id: UUID) {
    guard dependencies.onboardingCompleted() else { return }
    guard discoveryVisitID != id else { return }
    discoveryVisitID = id
    skipWidgetsThisVisit = firstVisitAfterOnboarding
    firstVisitAfterOnboarding = false
    historyTipShownThisVisit = false
    activeDiscoveryTip = nil
    closedWithResults = false
    var progress = dependencies.readDiscovery()
    guard progress.firstObservedAt == nil else { return }
    progress.firstObservedAt = dependencies.now()
    dependencies.saveDiscovery(progress)
  }

  /// Suspends transient tip eligibility when the foreground visit ends.
  public func endDiscoveryVisit() {
    suspendDiscoveryTips()
  }

  /// Evaluates history at the start of a subsequent editing interaction.
  public func offerHistoryTip() {
    guard activeDiscoveryTip == nil else { return }
    let progress = dependencies.readDiscovery()
    if progress.canOfferHistory(editing: editor != nil) {
      activeDiscoveryTip = .history
    }
  }

  /// Evaluates widgets after the keypad closes with useful converted results.
  public func offerWidgetsTip() {
    guard activeDiscoveryTip == nil else { return }
    let progress = dependencies.readDiscovery()
    if progress.canOfferWidgets(
      now: dependencies.now(), closedWithResults: closedWithResults,
      firstHomeVisit: skipWidgetsThisVisit, historyShownThisVisit: historyTipShownThisVisit)
    {
      activeDiscoveryTip = .widgets
    }
  }

  /// Records a tip only after native presentation reports it visible.
  public func discoveryTipPresented(_ tip: HomeDiscoveryTip) {
    guard activeDiscoveryTip == tip else { return }
    var progress = dependencies.readDiscovery()
    switch tip {
    case .history:
      progress.showedHistoryTip = true
      historyTipShownThisVisit = true
    case .widgets: progress.showedWidgetsTip = true
    }
    dependencies.saveDiscovery(progress)
  }

  /// Ends an offer when its presentation is dismissed or interrupted.
  public func endDiscoveryTip(_ tip: HomeDiscoveryTip) {
    if activeDiscoveryTip == tip { activeDiscoveryTip = nil }
  }

  /// Removes transient opportunities while another converter interaction owns focus.
  public func suspendDiscoveryTips() {
    activeDiscoveryTip = nil
    closedWithResults = false
  }

  /// Suppresses undiscovered history after opening details.
  public func visitDetails() {
    var progress = dependencies.readDiscovery()
    progress.visitedDetails = true
    dependencies.saveDiscovery(progress)
    suspendDiscoveryTips()
  }

  /// Suppresses undiscovered widgets after opening the toolbar guide.
  public func visitWidgets() {
    var progress = dependencies.readDiscovery()
    progress.openedWidgets = true
    dependencies.saveDiscovery(progress)
    suspendDiscoveryTips()
  }

  private func reconcileEditor() {
    guard let editor else { return }
    if !canEdit(editor.active, selectionID: editingSelectionID, in: input)
      || snapshot.convert(editor.decimal, from: editor.active, to: input.source) == nil
    {
      self.editor = nil
      editingSelectionID = nil
    }
  }

  private func canEdit(_ code: String, selectionID: String?, in state: ConverterState) -> Bool {
    if selectionID == state.source { return code == state.source }
    return state.destinationRows.contains { $0.id == selectionID && $0.code == code }
  }

  /// Ends temporary keypad input.
  public func endEditing() {
    let changed = recordCompletedEdit()
    closedWithResults =
      changed
      && input.destinations.contains {
        snapshot.convert(input.decimal, from: input.source, to: $0) != nil
      }
    editor = nil
    editStartingAmount = nil
    if activeDiscoveryTip == .history { activeDiscoveryTip = nil }
  }

  @discardableResult
  private func recordCompletedEdit() -> Bool {
    guard let editStartingAmount, editStartingAmount != input.decimal else { return false }
    var progress = dependencies.readDiscovery()
    progress.completedEdits += 1
    dependencies.saveDiscovery(progress)
    self.editStartingAmount = input.decimal
    return true
  }

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
  private func updateInput(_ mutation: (inout ConverterState) throws -> Void) -> Bool {
    do {
      input = try dependencies.editInput(mutation)
      if warning == .selectionSaveFailed { warning = dependencies.readRateIssue() }
      if let editor, !canEdit(editor.active, selectionID: editingSelectionID, in: input) {
        self.editor = nil
      }
      return true
    } catch EditingError.unavailableCurrency {
      editor = nil
      editingSelectionID = nil
      input = dependencies.readInput()
      return false
    } catch {
      warning = .selectionSaveFailed
      return false
    }
  }

  /// Changes the base currency using freshly read confirmed input.
  @discardableResult public func changeSource(_ code: String) -> Bool {
    updateInput { $0.changeSource(code) }
  }

  /// Adds a fixed destination or opts into the dynamic Local selection.
  @discardableResult public func addDestination(_ code: String) -> Bool {
    updateInput {
      if code == CurrencySelection.localID {
        $0.setUsesLocalCurrency(true)
      } else {
        $0.setDestinations($0.manualDestinations + [code])
      }
    }
  }

  /// Removes identified rows without losing edits committed by another host.
  @discardableResult public func removeDestinations(_ codes: [String]) -> Bool {
    updateInput { state in
      for code in codes { state.removeDestination(code) }
    }
  }

  /// Moves identified destinations relative to a stable row rather than stale indices.
  @discardableResult public func moveDestinations(_ codes: [String], before anchor: String?) -> Bool
  {
    updateInput { $0.moveDestinations(codes, before: anchor) }
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
      reconcileEditor()
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
