import ExchangeRates
import Foundation
import Settings
import Testing

@MainActor @Suite struct SettingsModelTests {
  private func dependencies(
    refresh: @escaping () async throws -> SettingsRateState = {
      SettingsRateState(snapshot: RateSnapshot(), codes: [])
    },
    replay: (() throws -> Void)? = nil,
    output: @escaping (SettingsOutput) -> Void = { _ in }
  ) -> SettingsDependencies {
    SettingsDependencies(
      readState: { SettingsRateState(snapshot: RateSnapshot(), codes: ["EUR", "USD"]) },
      changes: { AsyncStream<Void>(bufferingPolicy: .unbounded) { _ in } },
      readPreferences: { SettingsPreferences(theme: .system, accent: .primary) },
      setTheme: { _ in }, setAccent: { _ in }, refresh: refresh, replay: replay, output: output)
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
    continuation?.resume(returning: SettingsRateState(snapshot: RateSnapshot(), codes: ["JPY"]))
    await Task.yield()
    #expect(model.rates.codes == ["EUR", "USD"])
    #expect(!model.isRefreshing)
  }
  @Test func preferenceEditsUseOwnedCallbacks() {
    var preferences = SettingsPreferences(theme: .system, accent: .primary)
    let model = SettingsModel(
      dependencies: SettingsDependencies(
        readState: { SettingsRateState(snapshot: RateSnapshot(), codes: []) },
        changes: { AsyncStream<Void>(bufferingPolicy: .unbounded) { _ in } },
        readPreferences: { preferences },
        setTheme: { preferences.theme = $0 }, setAccent: { preferences.accent = $0 },
        refresh: { SettingsRateState(snapshot: RateSnapshot(), codes: []) }, replay: nil,
        output: { _ in }))
    model.setTheme(.dark)
    model.setAccent(.teal)
    #expect(model.preferences == SettingsPreferences(theme: .dark, accent: .teal))
  }
  @Test func hostCommitsRefreshDisplayedStateUntilFlowTeardown() async {
    var state = SettingsRateState(snapshot: RateSnapshot(), codes: ["EUR"])
    let stream = AsyncStream<Void>.makeStream()
    let model = SettingsModel(
      dependencies: SettingsDependencies(
        readState: { state }, changes: { stream.stream },
        readPreferences: { SettingsPreferences(theme: .system, accent: .primary) },
        setTheme: { _ in }, setAccent: { _ in }, refresh: { state }, replay: nil, output: { _ in }))
    let lifetime = Task { await model.run() }
    state.codes = ["EUR", "JPY"]
    stream.continuation.yield(())
    for _ in 0..<100 where model.rates.codes != state.codes { await Task.yield() }
    #expect(model.rates.codes == ["EUR", "JPY"])
    lifetime.cancel()
    await lifetime.value
    state.codes = ["USD"]
    stream.continuation.yield(())
    await Task.yield()
    #expect(model.rates.codes == ["EUR", "JPY"])
  }

}
