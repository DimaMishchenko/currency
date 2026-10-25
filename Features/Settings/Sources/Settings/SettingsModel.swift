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

/// App icon choices supported by Settings hosts.
public enum SettingsAppIcon: String, CaseIterable, Identifiable, Sendable {
  case world, worldEuro, worldPound, worldRupee, worldWon, worldBitcoin
  case grid, gridEuro, gridPound, gridRupee, gridWon, gridBitcoin
  /// Stable identity for the icon picker.
  public var id: Self { self }
  /// Visual family used to group the icon choices.
  public var style: SettingsAppIconStyle {
    switch self {
    case .world, .worldEuro, .worldPound, .worldRupee, .worldWon, .worldBitcoin: .world
    case .grid, .gridEuro, .gridPound, .gridRupee, .gridWon, .gridBitcoin: .grid
    }
  }
  /// Currency artwork paired with the fixed dollar artwork.
  public var currency: SettingsAppIconCurrency {
    switch self {
    case .world, .grid: .yenYuan
    case .worldEuro, .gridEuro: .euro
    case .worldPound, .gridPound: .pound
    case .worldRupee, .gridRupee: .rupee
    case .worldWon, .gridWon: .won
    case .worldBitcoin, .gridBitcoin: .bitcoin
    }
  }
}

/// Visual families offered by the app icon picker.
public enum SettingsAppIconStyle: String, CaseIterable, Identifiable, Sendable {
  case world, grid
  /// Stable identity for section rendering.
  public var id: Self { self }
  /// Ordered currency variants in this family.
  public var icons: [SettingsAppIcon] { SettingsAppIcon.allCases.filter { $0.style == self } }
}

/// Artwork currencies; the yen and yuan share their currency symbol.
public enum SettingsAppIconCurrency: String, CaseIterable, Sendable {
  case yenYuan, euro = "EUR", pound = "GBP", rupee = "INR", won = "KRW", bitcoin = "BTC"
}

/// An optional platform capability whose current icon remains authoritative in the host.
@MainActor
public struct SettingsAppIconCapability {
  /// Reads the icon currently applied by the platform.
  public var current: () -> SettingsAppIcon
  /// Applies an icon or throws if the platform cannot complete the change.
  public var select: (SettingsAppIcon) async throws -> Void
  /// Creates an app icon capability without feature-owned persistence.
  public init(
    current: @escaping () -> SettingsAppIcon,
    select: @escaping (SettingsAppIcon) async throws -> Void
  ) {
    self.current = current
    self.select = select
  }
}

/// Owned preference values independent of platform colors and persistence.
public struct SettingsPreferences: Sendable, Equatable {
  /// Preferred light, dark, or system appearance.
  public var theme: SettingsTheme
  /// Selected semantic accent preference.
  public var accent: SettingsAccent
  /// Preferred measurement shared by metal conversion surfaces.
  public var metalUnit: MetalUnit
  /// Whether interactive widgets request a short Taptic effect after successful actions.
  /// Physical output depends on device and platform behavior.
  public var widgetHapticsEnabled: Bool
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(
    theme: SettingsTheme, accent: SettingsAccent, metalUnit: MetalUnit = .troyOunce,
    widgetHapticsEnabled: Bool = false
  ) {
    self.theme = theme
    self.accent = accent
    self.metalUnit = metalUnit
    self.widgetHapticsEnabled = widgetHapticsEnabled
  }
}

/// Rate information supplied to the Settings flow.
public struct SettingsRateState: Sendable {
  /// The latest supplied rate or location observation.
  public var snapshot: RateSnapshot
  /// The converter source currency supplied by the host.
  public var base: String
  /// Ordered canonical currency codes used by this presentation.
  public var codes: [String]
  /// Recoverable provider condition accompanying the current rates.
  public var warning: RefreshWarning?
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(snapshot: RateSnapshot, base: String, codes: [String], warning: RefreshWarning? = nil)
  {
    self.snapshot = snapshot
    self.base = base
    self.codes = codes
    self.warning = warning
  }
}

/// Semantic requests interpreted by application coordination.
public enum SettingsOutput: Sendable { case manageLocation, replayed }
/// Recoverable operation failure localized by SettingsUI.
public enum SettingsIssue: Sendable, Equatable {
  case refreshFailed, replayFailed, preferenceSaveFailed, widgetHapticsSaveFailed,
    appIconChangeFailed
}

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
  /// Saves the shared measurement or throws without changing authoritative preferences.
  public var setMetalUnit: (MetalUnit) throws -> Void
  /// Saves widget feedback without changing authoritative preferences on failure.
  public var setWidgetHapticsEnabled: (Bool) throws -> Void
  /// Refreshes rates; callers coalesce repeated actions and reject superseded results.
  public var refresh: () async throws -> SettingsRateState
  /// Saves replay progress before emitting a successful replay outcome.
  public var replay: (() throws -> Void)?
  /// Optional icon support; hosts without this capability hide the picker.
  public var appIcon: SettingsAppIconCapability?
  /// Receives semantic outcomes and requests for application coordination.
  public var output: (SettingsOutput) -> Void
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(
    readState: @escaping () -> SettingsRateState,
    changes: @escaping () -> AsyncStream<Void>,
    readPreferences: @escaping () -> SettingsPreferences,
    setTheme: @escaping (SettingsTheme) -> Void,
    setAccent: @escaping (SettingsAccent) -> Void,
    setMetalUnit: @escaping (MetalUnit) throws -> Void,
    setWidgetHapticsEnabled: @escaping (Bool) throws -> Void,
    refresh: @escaping () async throws -> SettingsRateState,
    replay: (() throws -> Void)?,
    appIcon: SettingsAppIconCapability? = nil,
    output: @escaping (SettingsOutput) -> Void
  ) {
    self.readState = readState; self.changes = changes; self.readPreferences = readPreferences
    self.setTheme = setTheme; self.setAccent = setAccent; self.setMetalUnit = setMetalUnit
    self.setWidgetHapticsEnabled = setWidgetHapticsEnabled
    self.refresh = refresh
    self.replay = replay; self.appIcon = appIcon; self.output = output
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
  /// Icon last reconciled from the platform.
  public private(set) var selectedAppIcon: SettingsAppIcon?
  /// The icon being applied while the native operation completes.
  public private(set) var pendingAppIcon: SettingsAppIcon?
  private var appIconTask: Task<Void, Never>?
  private var appIconGeneration = UUID()
  private var refreshTask: Task<Void, Never>?
  private var generation = UUID()
  private var stopped = false
  private var preferenceRevision = 0
  /// Current authoritative preference values.
  public var preferences: SettingsPreferences {
    _ = preferenceRevision
    return dependencies.readPreferences()
  }
  /// Whether the host supplies the optional setup replay capability.
  public var allowsReplay: Bool { dependencies.replay != nil }
  /// Whether this host supports changing the app icon.
  public var allowsAppIconSelection: Bool { dependencies.appIcon != nil }
  /// Creates the owned value or model with explicit host inputs and operations.
  public init(dependencies: SettingsDependencies) {
    self.dependencies = dependencies
    rates = dependencies.readState()
    selectedAppIcon = dependencies.appIcon?.current()
  }
  /// Persists the selected theme through the host-owned preference capability.
  public func setTheme(_ value: SettingsTheme) {
    dependencies.setTheme(value)
    preferenceRevision += 1
  }
  /// Persists the selected accent through the host-owned preference capability.
  public func setAccent(_ value: SettingsAccent) {
    dependencies.setAccent(value)
    preferenceRevision += 1
  }
  /// Saves a measurement and exposes failure while retaining authoritative preferences.
  public func setMetalUnit(_ value: MetalUnit) {
    do {
      try dependencies.setMetalUnit(value)
      reload()
      if issue == .preferenceSaveFailed { issue = nil }
    } catch { issue = .preferenceSaveFailed }
  }
  /// Saves widget feedback and retains the host preference if saving fails.
  public func setWidgetHapticsEnabled(_ enabled: Bool) {
    guard !stopped else { return }
    do {
      try dependencies.setWidgetHapticsEnabled(enabled)
      reload()
      if issue == .widgetHapticsSaveFailed { issue = nil }
    } catch { issue = .widgetHapticsSaveFailed }
  }
  /// Reconciles the platform icon after returning to the active scene.
  public func reloadAppIcon() {
    guard !stopped else { return }
    selectedAppIcon = dependencies.appIcon?.current()
  }
  /// Coalesces repeated requests while retaining the applied selection until success.
  public func selectAppIcon(_ icon: SettingsAppIcon) {
    guard !stopped, appIconTask == nil, let capability = dependencies.appIcon else { return }
    reloadAppIcon()
    guard selectedAppIcon != icon else { return }
    let id = UUID()
    appIconGeneration = id
    pendingAppIcon = icon
    if issue == .appIconChangeFailed { issue = nil }
    appIconTask = Task {
      do {
        try await capability.select(icon)
        guard !Task.isCancelled, !stopped, appIconGeneration == id else { return }
        selectedAppIcon = capability.current()
      } catch {
        guard !Task.isCancelled, !stopped, appIconGeneration == id else { return }
        selectedAppIcon = capability.current()
        issue = .appIconChangeFailed
      }
      pendingAppIcon = nil
      appIconTask = nil
    }
  }
  /// Requests location management without opening another feature directly.
  public func manageLocation() {
    guard !stopped else { return }
    dependencies.output(.manageLocation)
  }
  /// Reconciles displayed state from the host-owned stores.
  public func reload() {
    rates = dependencies.readState()
    preferenceRevision += 1
    reloadAppIcon()
  }
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
    appIconGeneration = UUID(); appIconTask?.cancel(); appIconTask = nil; pendingAppIcon = nil
    generation = UUID(); refreshTask?.cancel(); refreshTask = nil; isRefreshing = false
  }
}
