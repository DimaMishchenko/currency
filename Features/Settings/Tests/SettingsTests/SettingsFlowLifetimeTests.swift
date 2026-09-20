import ExchangeRates
import Foundation
import Settings
import Testing

@MainActor
private final class SettingsLifetimeFixture {
  var rates = SettingsRateState(snapshot: RateSnapshot(), codes: ["EUR", "USD"])
  var subscriptions = 0
  var locationRequests = 0
  var refreshRequests = 0
  var changes: AsyncStream<Void>.Continuation?
  var pendingRefresh: CheckedContinuation<SettingsRateState, Never>?

  var dependencies: SettingsDependencies {
    .init(
      readState: { self.rates },
      changes: {
        self.subscriptions += 1
        return AsyncStream { self.changes = $0 }
      },
      readPreferences: { SettingsPreferences(theme: .system, accent: .primary) },
      setTheme: { _ in }, setAccent: { _ in },
      refresh: {
        self.refreshRequests += 1
        return await withCheckedContinuation { self.pendingRefresh = $0 }
      },
      replay: nil,
      output: { if case .manageLocation = $0 { self.locationRequests += 1 } })
  }

  func finishRefresh() {
    pendingRefresh?.resume(returning: SettingsRateState(snapshot: RateSnapshot(), codes: ["JPY"]))
    pendingRefresh = nil
  }
}

@MainActor
private func waitForSettings(_ predicate: () -> Bool) async {
  for _ in 0..<1000 {
    if predicate() { return }
    await Task.yield()
  }
  #expect(predicate(), "Timed out waiting for Settings flow lifetime")
}

@Suite @MainActor
struct SettingsFlowLifetimeTests {
  @Test func localNavigationReappearanceKeepsOneSubscriptionAndAnOperationalModel() async {
    let fixture = SettingsLifetimeFixture()
    let lifetime = SettingsFlowLifetime(dependencies: fixture.dependencies)
    lifetime.start()
    await waitForSettings { fixture.subscriptions == 1 }
    // Navigation covers the entry while this State-owned token remains alive.
    fixture.rates.codes = ["EUR", "GBP"]
    fixture.changes?.yield(())
    await waitForSettings { lifetime.model.rates.codes == ["EUR", "GBP"] }
    lifetime.start()
    await Task.yield()
    #expect(fixture.subscriptions == 1)
    lifetime.model.manageLocation()
    #expect(fixture.locationRequests == 1)
    lifetime.model.refresh()
    await waitForSettings { fixture.refreshRequests == 1 }
    fixture.finishRefresh()
    await waitForSettings { !lifetime.model.isRefreshing }
    #expect(lifetime.model.rates.codes == ["JPY"])
    lifetime.stop()
  }

  @Test func releasingEntryTokenCancelsRefreshAndRejectsItsLateResult() async throws {
    let fixture = SettingsLifetimeFixture()
    var lifetime: SettingsFlowLifetime? = SettingsFlowLifetime(dependencies: fixture.dependencies)
    weak var released = lifetime
    let model = try #require(lifetime?.model)
    lifetime?.start()
    await waitForSettings { fixture.subscriptions == 1 }
    model.refresh()
    await waitForSettings { fixture.pendingRefresh != nil }
    lifetime = nil
    #expect(released == nil)
    await waitForSettings { !model.isRefreshing }
    fixture.finishRefresh()
    await Task.yield()
    #expect(model.rates.codes == ["EUR", "USD"])
    model.manageLocation()
    #expect(fixture.locationRequests == 0)
  }

  @Test func explicitTeardownCannotRestartTheSameFlowIdentity() async {
    let fixture = SettingsLifetimeFixture()
    let lifetime = SettingsFlowLifetime(dependencies: fixture.dependencies)
    lifetime.start()
    await waitForSettings { fixture.subscriptions == 1 }
    lifetime.stop()
    lifetime.start()
    lifetime.model.refresh()
    await Task.yield()
    #expect(fixture.subscriptions == 1)
    #expect(fixture.refreshRequests == 0)
    #expect(!lifetime.model.isRefreshing)
  }
}
