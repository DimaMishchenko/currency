import ExchangeRates
import Foundation
import Observation
import Settings
import Synchronization
import Testing

@MainActor @Suite struct SettingsModelTests {
  private func dependencies(
    refresh: @escaping () async throws -> SettingsRateState = {
      SettingsRateState(snapshot: RateSnapshot(), base: "EUR", codes: [])
    },
    replay: (() throws -> Void)? = nil,
    appIcon: SettingsAppIconCapability? = nil,
    output: @escaping (SettingsOutput) -> Void = { _ in }
  ) -> SettingsDependencies {
    SettingsDependencies(
      readState: {
        SettingsRateState(snapshot: RateSnapshot(), base: "EUR", codes: ["EUR", "USD"])
      },
      changes: { AsyncStream<Void>(bufferingPolicy: .unbounded) { _ in } },
      readPreferences: { SettingsPreferences(theme: .system, accent: .primary) },
      setTheme: { _ in }, setAccent: { _ in }, setMetalUnit: { _ in }, refresh: refresh,
      replay: replay, appIcon: appIcon, output: output)
  }
  @Test func iconCatalogOffersEachCurrencyOnceInBothFamilies() {
    #expect(SettingsAppIcon.allCases.count == 12)
    #expect(Set(SettingsAppIcon.allCases.map(\.rawValue)).count == 12)
    for style in SettingsAppIconStyle.allCases {
      #expect(style.icons.count == 6)
      #expect(style.icons.map(\.currency) == SettingsAppIconCurrency.allCases)
    }
    #expect(SettingsAppIcon.world.style == .world)
    #expect(SettingsAppIcon.world.currency == .yenYuan)
    #expect(SettingsAppIcon.grid.style == .grid)
    #expect(SettingsAppIcon.grid.currency == .yenYuan)
  }

  @Test(arguments: SettingsAppIcon.allCases)
  func eachIconUsesPlatformStateAndSurvivesFlowRecreation(icon: SettingsAppIcon) async {
    var applied = SettingsAppIcon.world
    let capability = SettingsAppIconCapability(current: { applied }, select: { applied = $0 })
    let model = SettingsModel(dependencies: dependencies(appIcon: capability))
    model.selectAppIcon(icon)
    for _ in 0..<100 where model.pendingAppIcon != nil { await Task.yield() }
    #expect(model.selectedAppIcon == icon)
    #expect(applied == icon)
    model.stop()
    let reopened = SettingsModel(dependencies: dependencies(appIcon: capability))
    #expect(reopened.selectedAppIcon == icon)
    reopened.selectAppIcon(.world)
    for _ in 0..<100 where reopened.pendingAppIcon != nil { await Task.yield() }
    #expect(applied == .world)
    #expect(reopened.selectedAppIcon == .world)
  }

  @Test func hostsWithoutIconCapabilityHideSelection() {
    let model = SettingsModel(dependencies: dependencies())
    #expect(!model.allowsAppIconSelection)
    #expect(model.selectedAppIcon == nil)
    model.selectAppIcon(.grid)
    #expect(model.pendingAppIcon == nil)
  }

  @Test func iconSelectionUsesAppliedStateAndReconcilesExternalChanges() async {
    var applied = SettingsAppIcon.world
    var requested: [SettingsAppIcon] = []
    let model = SettingsModel(
      dependencies: dependencies(
        appIcon: SettingsAppIconCapability(
          current: { applied },
          select: {
            requested.append($0); applied = $0
          })))
    #expect(model.allowsAppIconSelection)
    model.selectAppIcon(.world)
    #expect(requested.isEmpty)
    model.selectAppIcon(.grid)
    #expect(model.selectedAppIcon == .world)
    #expect(model.pendingAppIcon == .grid)
    for _ in 0..<100 where model.pendingAppIcon != nil { await Task.yield() }
    #expect(requested == [.grid])
    #expect(model.selectedAppIcon == .grid)
    #expect(model.pendingAppIcon == nil)
    applied = .world
    model.reloadAppIcon()
    #expect(model.selectedAppIcon == .world)
  }

  @Test func failedIconChangePreservesPlatformSelectionAndCanRetry() async {
    var applied = SettingsAppIcon.world
    var failing = true
    let model = SettingsModel(
      dependencies: dependencies(
        appIcon: SettingsAppIconCapability(
          current: { applied },
          select: { icon in
            if failing { throw CocoaError(.fileWriteUnknown) }
            applied = icon
          })))
    model.selectAppIcon(.grid)
    for _ in 0..<100 where model.pendingAppIcon != nil { await Task.yield() }
    #expect(model.issue == .appIconChangeFailed)
    #expect(model.selectedAppIcon == .world)
    #expect(model.pendingAppIcon == nil)
    failing = false
    model.selectAppIcon(.grid)
    #expect(model.issue == nil)
    for _ in 0..<100 where model.pendingAppIcon != nil { await Task.yield() }
    #expect(model.selectedAppIcon == .grid)
  }

  @Test func duplicateIconRequestsCoalesceAndStoppedFlowRejectsLateSuccess() async {
    var applied = SettingsAppIcon.world
    var calls = 0
    var continuation: CheckedContinuation<Void, Never>?
    let model = SettingsModel(
      dependencies: dependencies(
        appIcon: SettingsAppIconCapability(
          current: { applied },
          select: { icon in
            calls += 1
            await withCheckedContinuation { continuation = $0 }
            applied = icon
          })))
    model.selectAppIcon(.grid)
    model.selectAppIcon(.grid)
    model.selectAppIcon(.world)
    for _ in 0..<100 where continuation == nil { await Task.yield() }
    #expect(calls == 1)
    #expect(model.pendingAppIcon == .grid)
    model.stop()
    continuation?.resume()
    for _ in 0..<100 where applied != .grid { await Task.yield() }
    #expect(applied == .grid)
    #expect(model.selectedAppIcon == .world)
    #expect(model.pendingAppIcon == nil)
    model.reloadAppIcon()
    model.selectAppIcon(.grid)
    #expect(model.selectedAppIcon == .world)
    #expect(calls == 1)
    #expect(model.issue == nil)
  }

  @Test func stoppedFlowRejectsLateIconFailure() async {
    var continuation: CheckedContinuation<Void, any Error>?
    let model = SettingsModel(
      dependencies: dependencies(
        appIcon: SettingsAppIconCapability(
          current: { .world },
          select: { _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
          })))
    model.selectAppIcon(.grid)
    for _ in 0..<100 where continuation == nil { await Task.yield() }
    model.stop()
    continuation?.resume(throwing: CocoaError(.fileWriteUnknown))
    for _ in 0..<10 { await Task.yield() }
    #expect(model.issue == nil)
    #expect(model.selectedAppIcon == .world)
    #expect(model.pendingAppIcon == nil)
  }

  @Test func failedReplayDoesNotEmitNavigationAndSuccessfulRetryCommitsFirst() {
    var failing = true
    var saved = false
    var emitted = false
    let model = SettingsModel(
      dependencies: dependencies(
        replay: {
          if failing { throw CocoaError(.fileWriteUnknown) }
          saved = true
        },
        output: { _ in
          #expect(saved)
          emitted = true
        }))
    #expect(!model.replay())
    #expect(model.issue == .replayFailed)
    #expect(!emitted)
    failing = false
    #expect(model.replay())
    #expect(emitted)
    #expect(model.issue == nil)
    #expect(!model.replay())
  }
  @Test func duplicateRefreshIsIgnoredAndStoppedFlowRejectsLateSuccess() async {
    var calls = 0
    var continuation: CheckedContinuation<SettingsRateState, Never>?
    let model = SettingsModel(
      dependencies: dependencies(refresh: {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
      }))
    model.refresh()
    model.refresh()
    while continuation == nil { await Task.yield() }
    #expect(calls == 1)
    model.stop()
    continuation?
      .resume(returning: SettingsRateState(snapshot: RateSnapshot(), base: "JPY", codes: ["JPY"]))
    await Task.yield()
    #expect(model.rates.codes == ["EUR", "USD"])
    #expect(!model.isRefreshing)
  }
  @Test func preferenceEditsUseOwnedCallbacks() {
    var preferences = SettingsPreferences(theme: .system, accent: .primary)
    let model = SettingsModel(
      dependencies: SettingsDependencies(
        readState: { SettingsRateState(snapshot: RateSnapshot(), base: "EUR", codes: []) },
        changes: { AsyncStream<Void>(bufferingPolicy: .unbounded) { _ in } },
        readPreferences: { preferences },
        setTheme: { preferences.theme = $0 }, setAccent: { preferences.accent = $0 },
        setMetalUnit: { preferences.metalUnit = $0 },
        refresh: { SettingsRateState(snapshot: RateSnapshot(), base: "EUR", codes: []) },
        replay: nil,
        output: { _ in }))
    model.setTheme(.dark)
    model.setAccent(.teal)
    model.setMetalUnit(.gram)
    #expect(model.preferences == SettingsPreferences(theme: .dark, accent: .teal, metalUnit: .gram))
  }
  @Test func measurementSaveInvalidatesObservedPreferencesWithoutRateChanges() {
    let state = SettingsRateState(snapshot: RateSnapshot(), base: "EUR", codes: ["EUR", "USD"])
    var preferences = SettingsPreferences(theme: .system, accent: .primary)
    let model = SettingsModel(
      dependencies: SettingsDependencies(
        readState: { state }, changes: { AsyncStream { $0.finish() } },
        readPreferences: { preferences }, setTheme: { preferences.theme = $0 },
        setAccent: { preferences.accent = $0 }, setMetalUnit: { preferences.metalUnit = $0 },
        refresh: { state }, replay: nil, output: { _ in }))
    let invalidated = Mutex(false)
    withObservationTracking {
      #expect(model.preferences.metalUnit == .troyOunce)
    } onChange: {
      invalidated.withLock { $0 = true }
    }

    model.setMetalUnit(.gram)

    #expect(invalidated.withLock { $0 })
    #expect(model.preferences.metalUnit == .gram)
    #expect(model.rates.codes == state.codes)
    #expect(model.rates.snapshot.fetchedAt == state.snapshot.fetchedAt)
  }

  @Test func hostPreferenceCommitInvalidatesObservationWithoutRateChanges() async {
    let state = SettingsRateState(snapshot: RateSnapshot(), base: "EUR", codes: ["EUR", "USD"])
    var preferences = SettingsPreferences(theme: .system, accent: .primary)
    let stream = AsyncStream<Void>.makeStream()
    var subscribed = false
    let model = SettingsModel(
      dependencies: SettingsDependencies(
        readState: { state },
        changes: {
          subscribed = true
          return stream.stream
        },
        readPreferences: { preferences }, setTheme: { preferences.theme = $0 },
        setAccent: { preferences.accent = $0 }, setMetalUnit: { preferences.metalUnit = $0 },
        refresh: { state }, replay: nil, output: { _ in }))
    let lifetime = Task { await model.run() }
    for _ in 0..<1000 where !subscribed { await Task.yield() }
    #expect(subscribed)
    let invalidated = Mutex(false)
    withObservationTracking {
      #expect(model.preferences.metalUnit == .troyOunce)
    } onChange: {
      invalidated.withLock { $0 = true }
    }

    preferences.metalUnit = .kilogram
    stream.continuation.yield(())
    for _ in 0..<1000 where !invalidated.withLock({ $0 }) { await Task.yield() }

    #expect(invalidated.withLock { $0 })
    #expect(model.preferences.metalUnit == .kilogram)
    #expect(model.rates.codes == state.codes)
    #expect(model.rates.snapshot.fetchedAt == state.snapshot.fetchedAt)
    lifetime.cancel()
    await lifetime.value
  }

  @Test func failedMeasurementSavePreservesAuthoritativePreference() {
    let model = SettingsModel(
      dependencies: SettingsDependencies(
        readState: { SettingsRateState(snapshot: RateSnapshot(), base: "EUR", codes: []) },
        changes: { AsyncStream { $0.finish() } },
        readPreferences: { SettingsPreferences(theme: .system, accent: .primary) },
        setTheme: { _ in }, setAccent: { _ in },
        setMetalUnit: { _ in throw CocoaError(.fileWriteUnknown) },
        refresh: { SettingsRateState(snapshot: RateSnapshot(), base: "EUR", codes: []) },
        replay: nil, output: { _ in }))
    model.setMetalUnit(.gram)
    #expect(model.preferences.metalUnit == .troyOunce)
    #expect(model.issue == .preferenceSaveFailed)
  }

  @Test func hostCommitsRefreshDisplayedStateUntilFlowTeardown() async {
    var state = SettingsRateState(snapshot: RateSnapshot(), base: "EUR", codes: ["EUR"])
    let stream = AsyncStream<Void>.makeStream()
    let model = SettingsModel(
      dependencies: SettingsDependencies(
        readState: { state }, changes: { stream.stream },
        readPreferences: { SettingsPreferences(theme: .system, accent: .primary) },
        setTheme: { _ in }, setAccent: { _ in }, setMetalUnit: { _ in }, refresh: { state },
        replay: nil, output: { _ in }))
    let lifetime = Task { await model.run() }
    state.base = "JPY"
    state.codes = ["EUR", "JPY"]
    stream.continuation.yield(())
    for _ in 0..<100 where model.rates.codes != state.codes { await Task.yield() }
    #expect(model.rates.codes == ["EUR", "JPY"])
    #expect(model.rates.base == "JPY")
    lifetime.cancel()
    await lifetime.value
    state.base = "USD"
    state.codes = ["USD"]
    stream.continuation.yield(())
    await Task.yield()
    #expect(model.rates.codes == ["EUR", "JPY"])
    #expect(model.rates.base == "JPY")
  }

}
