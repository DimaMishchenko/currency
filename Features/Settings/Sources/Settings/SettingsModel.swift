import ExchangeRates
import Foundation
import Observation

/// Appearance choices belong to Settings, independent of app persistence and SwiftUI.
public enum SettingsTheme: String, CaseIterable, Identifiable, Sendable {
  case system, light, dark
  /// Stable identity for selection controls.
  public var id: Self { self }
}

/// Named preference values mapped to visual colors by UI composition.
public enum SettingsAccent: String, CaseIterable, Identifiable, Sendable {
  case primary, blue, indigo, purple, pink, red, orange, green, teal
  /// Stable identity for selection controls.
  public var id: Self { self }
}

/// Owned preference values independent of platform colors and persistence.
public struct SettingsPreferences: Sendable, Equatable {
  /// Preferred light, dark, or system appearance.
  public var theme: SettingsTheme
  /// Selected semantic accent preference.
  public var accent: SettingsAccent
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(theme: SettingsTheme, accent: SettingsAccent) {
    self.theme = theme
    self.accent = accent
  }
}

/// Rate information supplied to the Settings flow.
public struct SettingsRateState: Sendable {
  /// The latest supplied rate or location observation.
  public var snapshot: RateSnapshot
  /// Ordered canonical currency codes used by this presentation.
  public var codes: [String]
  /// Recoverable provider condition accompanying the current rates.
  public var warning: RefreshWarning?
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(snapshot: RateSnapshot, codes: [String], warning: RefreshWarning? = nil) {
    self.snapshot = snapshot
    self.codes = codes
    self.warning = warning
  }
}

/// Semantic requests interpreted by application coordination.
public enum SettingsOutput: Sendable { case manageLocation, replayed }
/// Recoverable operation failure localized by SettingsUI.
public enum SettingsIssue: Sendable, Equatable { case refreshFailed, replayFailed }

/// The host supplies preference persistence and operations; Settings owns their presentation flow.
@MainActor
public struct SettingsDependencies {
  /// Reads the host current rate information without starting network work.
  public var readState: () -> SettingsRateState
  /// Subscribes to committed host state changes; each flow owns its subscription.
  public var changes: () -> AsyncStream<Void>
  /// Reads authoritative preferences; observable host reads remain tracked by UI.
  public var readPreferences: () -> SettingsPreferences
  /// Persists the selected theme through the host-owned preference capability.
  public var setTheme: (SettingsTheme) -> Void
  /// Persists the selected accent through the host-owned preference capability.
  public var setAccent: (SettingsAccent) -> Void
  /// Refreshes rates; callers coalesce repeated actions and reject superseded results.
  public var refresh: () async throws -> SettingsRateState
  /// Saves replay progress before emitting a successful replay outcome.
  public var replay: (() throws -> Void)?
  /// Receives semantic outcomes and requests for application coordination.
  public var output: (SettingsOutput) -> Void
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(
    readState: @escaping () -> SettingsRateState,
    changes: @escaping () -> AsyncStream<Void>,
    readPreferences: @escaping () -> SettingsPreferences,
    setTheme: @escaping (SettingsTheme) -> Void,
    setAccent: @escaping (SettingsAccent) -> Void,
    refresh: @escaping () async throws -> SettingsRateState,
    replay: (() throws -> Void)?, output: @escaping (SettingsOutput) -> Void
  ) {
    self.readState = readState; self.changes = changes; self.readPreferences = readPreferences
    self.setTheme = setTheme; self.setAccent = setAccent; self.refresh = refresh
    self.replay = replay; self.output = output
  }
}

/// One Settings flow. Hosts call stop on actual flow teardown.
@MainActor @Observable
public final class SettingsModel {
  private let dependencies: SettingsDependencies
  /// Current rate information displayed by this flow.
  public private(set) var rates: SettingsRateState
  /// Whether this flow has a manual refresh in flight.
  public private(set) var isRefreshing = false
  /// Current recoverable operation failure.
  public private(set) var issue: SettingsIssue?
  private var refreshTask: Task<Void, Never>?
  private var generation = UUID()
  private var stopped = false
  /// Current authoritative preference values.
  public var preferences: SettingsPreferences { dependencies.readPreferences() }
  /// Whether the host supplies the optional setup replay capability.
  public var allowsReplay: Bool { dependencies.replay != nil }
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(dependencies: SettingsDependencies) {
    self.dependencies = dependencies
    rates = dependencies.readState()
  }
  /// Persists the selected theme through the host-owned preference capability.
  public func setTheme(_ value: SettingsTheme) { dependencies.setTheme(value) }
  /// Persists the selected accent through the host-owned preference capability.
  public func setAccent(_ value: SettingsAccent) { dependencies.setAccent(value) }
  /// Requests location management without opening another feature directly.
  public func manageLocation() {
    guard !stopped else { return }
    dependencies.output(.manageLocation)
  }
  /// Reconciles displayed rates from the host-owned state.
  public func reload() { rates = dependencies.readState() }
  /// Refreshes rates; callers coalesce repeated actions and reject superseded results.
  public func refresh() {
    guard !stopped, refreshTask == nil else { return }
    let id = UUID(); generation = id
    isRefreshing = true; issue = nil
    refreshTask = Task {
      do {
        let value = try await dependencies.refresh()
        guard !Task.isCancelled, generation == id else { return }
        rates = value
      } catch {
        guard !Task.isCancelled, generation == id else { return }
        issue = .refreshFailed
      }
      isRefreshing = false; refreshTask = nil
    }
  }
  /// Saves replay progress before emitting a successful replay outcome.
  @discardableResult
  public func replay() -> Bool {
    guard !stopped, let replay = dependencies.replay else { return false }
    do {
      try replay()
      issue = nil
      stop()
      dependencies.output(.replayed)
      return true
    } catch { issue = .replayFailed; return false }
  }
  /// Dismisses the current recoverable failure.
  public func clearIssue() { issue = nil }
  /// Remains active for the outer entry lifetime; local navigation does not replace this host.
  public func run() async {
    await withTaskCancellationHandler {
      let changes = dependencies.changes()
      reload()
      for await _ in changes {
        guard !stopped, !Task.isCancelled else { break }
        reload()
      }
      stop()
    } onCancel: {
      Task { @MainActor [weak self] in self?.stop() }
    }
  }
  /// Ends this flow operation lifetime and rejects results arriving after teardown.
  public func stop() {
    stopped = true
    generation = UUID(); refreshTask?.cancel(); refreshTask = nil; isRefreshing = false
  }
}
