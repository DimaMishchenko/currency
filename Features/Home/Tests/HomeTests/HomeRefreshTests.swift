import Conversion
import ExchangeRates
import Foundation
import Home
import Testing

@MainActor
private final class HomeRefreshFixture {
  var input = ConverterState()
  var snapshot = RateSnapshot()
  var count = 0
  var rateIssue: HomeIssue?
  var rejectsInput = false
  var requests: [Int: CheckedContinuation<RefreshResult, any Error>] = [:]
  var notifications: AsyncStream<Void>.Continuation?

  var dependencies: HomeDependencies {
    .init(
      readInput: { self.input }, readRates: { self.snapshot },
      readRateIssue: { self.rateIssue },
      readLocalCurrency: { (nil, .notDetermined) },
      editInput: { edit in
        if self.rejectsInput { throw CocoaError(.fileWriteOutOfSpace) }
        try edit(&self.input); return self.input
      },
      refreshRates: { _ in
        self.count += 1
        let index = self.count
        return try await withCheckedThrowingContinuation { self.requests[index] = $0 }
      },
      changes: { AsyncStream { self.notifications = $0 } })
  }

  func succeed(_ index: Int, warning: RefreshWarning? = nil) {
    rateIssue = warning.map(HomeIssue.rateWarning)
    requests.removeValue(forKey: index)?
      .resume(returning: RefreshResult(snapshot: snapshot, warning: warning))
  }

  func fail(_ index: Int) {
    rateIssue = .rateSaveFailed
    requests.removeValue(forKey: index)?.resume(throwing: CocoaError(.fileWriteOutOfSpace))
  }
}

@MainActor
private func waitForHome(_ condition: () -> Bool) async {
  for _ in 0..<1000 {
    if condition() { return }
    await Task.yield()
  }
  #expect(condition(), "Timed out waiting for the manual refresh operation")
}

@Suite @MainActor
struct HomeRefreshTests {
  @Test func foregroundRateWarningsAndSaveFailuresReachExistingHome() async {
    let fixture = HomeRefreshFixture()
    let model = HomeModel(dependencies: fixture.dependencies)
    let observation = Task { await model.observeChanges() }
    await waitForHome { fixture.notifications != nil }
    fixture.rateIssue = .rateWarning(.dailyRatesUnavailable)
    fixture.notifications?.yield(())
    await waitForHome { model.warning == .rateWarning(.dailyRatesUnavailable) }
    fixture.rateIssue = .rateSaveFailed
    fixture.notifications?.yield(())
    await waitForHome { model.warning == .rateSaveFailed }
    fixture.rateIssue = nil
    fixture.notifications?.yield(())
    await waitForHome { model.warning == nil }
    observation.cancel()
    await observation.value
  }

  @Test func unrelatedSharedChangesKeepSelectionSaveFailureUntilSuccessfulManualRefresh() async {
    let fixture = HomeRefreshFixture()
    fixture.rejectsInput = true
    let model = HomeModel(dependencies: fixture.dependencies)
    #expect(!model.updateInput { $0.setAmount("42") })
    #expect(model.warning == .selectionSaveFailed)
    fixture.rateIssue = .rateWarning(.partialCryptoFallback)
    model.reloadSharedState()
    #expect(model.warning == .selectionSaveFailed)
    fixture.rateIssue = nil
    model.reloadSharedState()
    #expect(model.warning == .selectionSaveFailed)
    let refresh = Task { await model.refresh(force: true) }
    await waitForHome { fixture.count == 1 }
    fixture.succeed(1)
    #expect(await refresh.value == .refreshed)
    #expect(model.warning == nil)
  }

  @Test func restoredHomeReadsExistingSharedRateIssue() {
    let fixture = HomeRefreshFixture()
    fixture.rateIssue = .rateWarning(.partialCryptoFallback)
    let model = HomeModel(dependencies: fixture.dependencies)
    #expect(model.warning == .rateWarning(.partialCryptoFallback))
  }

  @Test func repeatedManualRequestIsIgnoredWithoutStartingAnotherOperation() async {
    let fixture = HomeRefreshFixture()
    let model = HomeModel(dependencies: fixture.dependencies)
    let first = Task { await model.refresh(force: true) }
    await waitForHome { fixture.count == 1 }
    #expect(await model.refresh(force: true) == .ignored)
    #expect(fixture.count == 1)
    fixture.succeed(1)
    #expect(await first.value == .refreshed)
    #expect(!model.manuallyRefreshing)
  }

  @Test func cancelledNoncooperatingFailureCannotReplaceNewerRefresh() async {
    let fixture = HomeRefreshFixture()
    let model = HomeModel(dependencies: fixture.dependencies)
    let first = Task { await model.refresh(force: true) }
    await waitForHome { fixture.count == 1 }
    first.cancel()
    await waitForHome { !model.refreshing }
    let second = Task { await model.refresh(force: true) }
    await waitForHome { fixture.count == 2 }
    fixture.fail(1)
    #expect(await first.value == .cancelled)
    #expect(model.manuallyRefreshing)
    #expect(model.warning == nil)
    fixture.succeed(2, warning: .dailyRatesUnavailable)
    #expect(await second.value == .warning)
    #expect(model.warning == .rateWarning(.dailyRatesUnavailable))
    #expect(!model.refreshing)
  }

  @Test func storageFailureHasDistinctTypedOutcome() async {
    let fixture = HomeRefreshFixture()
    let model = HomeModel(dependencies: fixture.dependencies)
    let request = Task { await model.refresh(force: true) }
    await waitForHome { fixture.count == 1 }
    fixture.fail(1)
    #expect(await request.value == .failed)
    #expect(model.warning == .rateSaveFailed)
    #expect(!model.manuallyRefreshing)
  }

  @Test func sharedStateNotificationUpdatesRatesAndPreservesUnchangedEditor() async {
    let fixture = HomeRefreshFixture()
    fixture.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .ecb)),
      "USD": ExchangeRate(2, published: "2026-09-19", source: .init(provider: .ecb))
    ])
    let model = HomeModel(dependencies: fixture.dependencies)
    model.beginEditing("USD")
    let original = model.editor
    let observation = Task { await model.observeChanges() }
    await waitForHome { fixture.notifications != nil }
    fixture.snapshot = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-20", source: .init(provider: .ecb)),
      "USD": ExchangeRate(3, published: "2026-09-20", source: .init(provider: .ecb))
    ])
    fixture.notifications?.yield(())
    await waitForHome { model.snapshot.quotes["USD"]?.value == 3 }
    #expect(model.editor == original)
    fixture.input.setAmount("42")
    fixture.notifications?.yield(())
    await waitForHome { model.input.amount == "42" }
    #expect(model.editor == nil)
    observation.cancel()
    await observation.value
  }
}
