import CurrencySupport
import ExchangeRates
import Foundation
import Observation

/// Owns first-launch data, draft selection, resumability, and bounded request identity.
/// Views animate independently and never supply manufactured rates to this model.
@MainActor @Observable
final class OnboardingModel {
  /// The persistent scenes in first-launch setup.
  typealias Step = OnboardingProgress.Step
  /// The current foreground rate-loading or recovery presentation.
  enum Phase: Sendable {
    case opening, waiting, ready, offline, failed, retrying, saveFailed
  }
  /// Identifies the local operation that needs a storage retry.
  enum SaveError: Sendable { case rates, selection, completion, draft }

  /// Latency and storage seams keep failure and lifecycle checks deterministic.
  struct Configuration {
    /// Time before the initial waiting indicator becomes visible.
    var loadingDelay: Duration
    /// Maximum foreground attempt duration, independent of provider cooperation.
    var deadline: Duration
    /// Evaluation clock for cache and retrieval timestamp validation.
    var now: @MainActor () -> Date
    /// Optional storage fault seam used by deterministic model tests.
    var beforeSave: (@MainActor (SaveError) throws -> Void)?

    /// Creates bootstrap timing and persistence dependencies.
    init(
      loadingDelay: Duration = .milliseconds(1200), deadline: Duration = .seconds(12),
      now: @escaping @MainActor () -> Date = { .now },
      beforeSave: (@MainActor (SaveError) throws -> Void)? = nil
    ) {
      self.loadingDelay = loadingDelay
      self.deadline = deadline
      self.now = now
      self.beforeSave = beforeSave
    }
  }

  /// The last successfully persisted snapshot used by all previews.
  private(set) var snapshot: RateSnapshot
  /// Editable choices that remain separate from production converter input.
  private(set) var draft: ConverterState
  /// The active persisted scene.
  private(set) var step: Step
  /// The rate-bootstrap presentation state.
  private(set) var phase: Phase = .opening
  /// True only after a successful completion commit.
  private(set) var isCompleted: Bool
  /// A recoverable local storage failure, never a network classification.
  private(set) var saveError: SaveError?
  /// Whether one foreground request attempt currently owns state.
  private(set) var isRefreshing = false

  @ObservationIgnored private let store: CurrencyStore
  @ObservationIgnored private let service: RateService
  @ObservationIgnored private let configuration: Configuration
  @ObservationIgnored private var attempt: UUID?
  @ObservationIgnored private var request: Task<Void, Never>?
  @ObservationIgnored private var waiting: Task<Void, Never>?
  @ObservationIgnored private var deadline: Task<Void, Never>?
  @ObservationIgnored private var pendingSnapshot: RateSnapshot?
  @ObservationIgnored private var pendingStep: Step?
  @ObservationIgnored private var started = false
  @ObservationIgnored private var didBecomeReady = false
  @ObservationIgnored private var active = true
  @ObservationIgnored private var refreshOnResume = false

  /// Restores cached rates and the unfinished draft without starting network work.
  init(
    store: CurrencyStore = .shared, service: RateService = RateService(),
    configuration: Configuration = .init()
  ) {
    self.store = store
    self.service = service
    self.configuration = configuration
    let saved = store.onboardingProgress()
    var initial = ConverterState()
    initial.setAmount("100")
    initial.setDestinations(["USD"])
    draft = saved?.draft ?? initial
    step = saved?.step ?? .welcome
    isCompleted = saved?.completed == true && saved?.version == 1
    let cached = store.loadRates()
    snapshot = cached.hasValidFetchTimestamp(now: configuration.now()) ? cached : RateSnapshot()
    if hasUsableRates {
      phase = .ready
      didBecomeReady = true
    }
  }

  /// A destination is usable only when conversion and real fetch metadata are valid.
  func isAvailable(_ code: String) -> Bool {
    if code == draft.source {
      guard let value = snapshot.quotes[code]?.value else { return false }
      return !value.isNaN && value > 0
    }
    return snapshot.hasUsablePair(
      from: draft.source, to: code, amount: 100, now: configuration.now())
  }

  /// A replacement base needs its own usable quote, even when the old base lost coverage.
  func canUseAsBase(_ code: String) -> Bool {
    guard CurrencyCatalog.codes.contains(code),
      snapshot.hasValidFetchTimestamp(now: configuration.now()),
      let value = snapshot.quotes[code]?.value
    else { return false }
    return !value.isNaN && value > 0
  }

  /// Prefers USD, then the ordered draft, then a deterministic available fallback.
  var welcomeDestination: String? {
    (["USD"] + draft.destinations + snapshot.quotes.keys.sorted())
      .first { $0 != draft.source && isAvailable($0) }
  }

  /// Whether the base has at least one supported, positive, persisted conversion.
  var hasUsableRates: Bool { welcomeDestination != nil }
  /// Whether persisted rates contain a valid pair for explicitly choosing a replacement base.
  var hasRecoveryRates: Bool { containsUsablePair(snapshot) }
  /// Whether the current destination selection includes at least one usable conversion.
  var canContinue: Bool { draft.destinations.contains(where: isAvailable) }
  /// Real snapshot retrieval time; failed refresh attempts do not replace it.
  var lastUpdated: Date? { hasUsableRates ? snapshot.fetchedAt : nil }

  /// Starts bootstrap once; valid cache is available synchronously before this call.
  func start() {
    guard !started, !isCompleted else { return }
    started = true
    begin(retrying: false)
  }

  /// Retries a failed request or pending save while ignoring repeated in-flight taps.
  func retry() {
    guard active, !isCompleted, !isRefreshing else { return }
    if saveError != nil { retrySave(); return }
    begin(retrying: true)
  }

  /// Backgrounding invalidates ownership before cancelling; late results cannot alter the UI.
  func pause() {
    active = false
    refreshOnResume = refreshOnResume || isRefreshing
    cancelAttempt()
  }

  /// Resumes an interrupted request without replaying the entrance or losing the draft.
  func resume() {
    active = true
    guard !isCompleted else { return }
    if !started {
      start()
    } else if refreshOnResume {
      refreshOnResume = false
      begin(retrying: false)
    }
  }

  /// Toggles one destination without reordering others; an empty draft remains empty.
  func toggle(_ code: String) {
    guard !isCompleted, CurrencyCatalog.codes.contains(code), code != draft.source else { return }
    var codes = draft.destinations
    if let index = codes.firstIndex(of: code) {
      codes.remove(at: index)
    } else {
      guard isAvailable(code) else { return }
      codes.append(code)
    }
    draft.setDestinations(codes)
    persistDraft()
  }

  /// Changes base with the converter's deterministic destination swap.
  func changeBase(_ code: String) {
    guard !isCompleted, canUseAsBase(code), code != draft.source else { return }
    draft.changeSource(code)
    if hasUsableRates { phase = .ready }
    persistDraft()
  }

  /// Opens the base choice after a persisted usable welcome pair is available.
  func continueFromWelcome() {
    guard step == .welcome, hasUsableRates, !isCompleted else { return }
    // The displayed alternate pair is the explicit initial selection when USD is unavailable.
    if draft.destinations == ["USD"], !isAvailable("USD"), let code = welcomeDestination {
      draft.setDestinations([code])
    }
    move(to: .baseCurrency)
  }

  /// Confirms the draft base before choosing destinations, without changing app input.
  func continueFromBaseCurrency() {
    guard step == .baseCurrency, hasUsableRates, !isCompleted else { return }
    move(to: .selection)
  }

  /// Atomically saves base and destinations, then persists the Home Screen context stage.
  func continueFromSelection() {
    guard step == .selection, canContinue, !isCompleted else { return }
    do {
      try configuration.beforeSave?(.selection)
      let selection = draft
      // Preserve the latest app/widget amount; the onboarding 100 is only a preview.
      try store.updateInput {
        $0.changeSource(selection.source)
        $0.setDestinations(selection.destinations)
      }
      try saveProgress(step: .homeScreen)
      step = .homeScreen
      saveError = nil
    } catch { saveError = .selection }
  }

  /// Advances from Home Screen context to the production widget showcase after saving progress.
  func continueFromHomeScreen() {
    guard step == .homeScreen, !isCompleted else { return }
    move(to: .widgets)
  }

  /// Returns to the preceding scene while retaining all draft choices.
  func back() {
    guard !isCompleted else { return }
    switch step {
    case .welcome: break
    case .baseCurrency: move(to: .welcome)
    case .selection: move(to: .baseCurrency)
    case .homeScreen: move(to: .selection)
    case .widgets: move(to: .homeScreen)
    }
  }

  /// Both Later and a finished/skipped installation guide use this same local commit.
  @discardableResult
  func complete() -> Bool {
    guard step == .widgets else { return false }
    if isCompleted { return true }
    do {
      try configuration.beforeSave?(.completion)
      try saveProgress(step: .widgets, completed: true)
      isCompleted = true
      saveError = nil
      cancelAttempt()
      return true
    } catch {
      saveError = .completion
      return false
    }
  }

  /// Reopens setup with today's app choices, preserving app input and cached rates.
  /// Completion remains intact if the new progress record cannot be saved.
  func restart() throws {
    var current = store.input()
    current.setAmount("100")
    try configuration.beforeSave?(.draft)
    try store.saveOnboardingProgress(OnboardingProgress(draft: current, step: .welcome))
    cancelAttempt()
    draft = current
    step = .welcome
    isCompleted = false
    saveError = nil
    pendingStep = nil
    pendingSnapshot = nil
    started = false
    active = true
    refreshOnResume = false
    let cached = store.loadRates()
    snapshot = cached.hasValidFetchTimestamp(now: configuration.now()) ? cached : RateSnapshot()
    didBecomeReady = hasUsableRates
    phase = hasUsableRates ? .ready : .opening
  }

  /// Repeats only the failed local operation, without refetching or replaying a guide.
  func retrySave() {
    switch saveError {
    case .rates:
      guard let pendingSnapshot else { return }
      accept(pendingSnapshot)
    case .selection: continueFromSelection()
    case .completion: _ = complete()
    case .draft:
      if let pendingStep { move(to: pendingStep) } else { persistDraft() }
    case nil: break
    }
  }

  private func move(to next: Step) {
    pendingStep = next
    do {
      try configuration.beforeSave?(.draft)
      try saveProgress(step: next)
      step = next
      pendingStep = nil
      saveError = nil
    } catch { saveError = .draft }
  }

  private func persistDraft() {
    do {
      try configuration.beforeSave?(.draft)
      try saveProgress(step: step)
      saveError = nil
    } catch { saveError = .draft }
  }

  private func saveProgress(step: Step, completed: Bool = false) throws {
    try store.saveOnboardingProgress(
      OnboardingProgress(draft: draft, step: step, completed: completed))
  }

  private func begin(retrying: Bool) {
    cancelAttempt()
    let identity = UUID()
    attempt = identity
    isRefreshing = true
    if !hasUsableRates { phase = retrying ? .retrying : .opening }
    waiting = Task { [weak self, delay = configuration.loadingDelay] in
      do { try await Task.sleep(for: delay) } catch { return }
      guard let self, attempt == identity, !hasUsableRates, saveError == nil else { return }
      if phase != .retrying { phase = .waiting }
    }
    deadline = Task { [weak self, delay = configuration.deadline] in
      do { try await Task.sleep(for: delay) } catch { return }
      guard let self, attempt == identity else { return }
      cancelAttempt()
      if !hasUsableRates, saveError == nil { phase = .failed }
    }
    request = Task { [weak self, service, previous = snapshot, now = configuration.now()] in
      let updates = await service.bootstrap(previous: previous, now: now)
      for await update in updates {
        guard let self, attempt == identity, active, !Task.isCancelled else { return }
        accept(update.snapshot)
        if update.isFinal {
          isRefreshing = false
          waiting?.cancel()
          deadline?.cancel()
          attempt = nil
          if !hasUsableRates, saveError == nil {
            phase = update.failure == .offline ? .offline : .failed
          }
        }
      }
    }
  }

  private func accept(_ incoming: RateSnapshot) {
    // Do not persist an identity-only/invalid response as the first usable rate snapshot.
    let valid = incoming.quotes.keys.contains {
      incoming.hasUsablePair(from: draft.source, to: $0, now: configuration.now())
    }
    // Once ready, later provider failures can honestly remove live quotes without a daily
    // fallback. Keep selections while marking them unavailable; never resurrect that overlay.
    // A saved base may also be unavailable on welcome, which exposes explicit base recovery.
    let recoveryPair = containsUsablePair(incoming)
    guard valid || recoveryPair || didBecomeReady else { return }
    do {
      try configuration.beforeSave?(.rates)
      snapshot = try store.saveBootstrapRates(incoming, now: configuration.now())
      pendingSnapshot = nil
      if saveError == .rates { saveError = nil }
      if hasUsableRates { didBecomeReady = true }
      phase = .ready
    } catch {
      pendingSnapshot = incoming
      if !hasUsableRates { phase = .saveFailed }
      if saveError == nil || saveError == .rates { saveError = .rates }
    }
  }

  private func containsUsablePair(_ rates: RateSnapshot) -> Bool {
    rates.quotes.keys.contains { base in
      rates.quotes.keys.contains {
        rates.hasUsablePair(from: base, to: $0, now: configuration.now())
      }
    }
  }

  private func cancelAttempt() {
    attempt = nil
    request?.cancel()
    waiting?.cancel()
    deadline?.cancel()
    request = nil
    waiting = nil
    deadline = nil
    isRefreshing = false
  }
}
