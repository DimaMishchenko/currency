import CurrencySupport
import ExchangeRates
import Foundation
import Testing

@testable import OnboardingFeature

private struct OnboardingProvider: RateProvider {
  var quotes: [String: ExchangeRate] = [:]
  var delay: Duration = .zero
  var error: URLError.Code?

  func fetch() async throws -> [String: ExchangeRate] {
    try await Task.sleep(for: delay)
    if let error { throw URLError(error) }
    return quotes
  }
}

private actor LateOnboardingProvider: RateProvider {
  private var continuation: CheckedContinuation<[String: ExchangeRate], any Error>?
  private(set) var started = false

  func fetch() async throws -> [String: ExchangeRate] {
    started = true
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func finish() {
    continuation?.resume(returning: onboardingQuotes())
    continuation = nil
  }
}

private actor RetriedOnboardingProvider: RateProvider {
  private var continuation: CheckedContinuation<[String: ExchangeRate], any Error>?
  private(set) var count = 0

  func fetch() async throws -> [String: ExchangeRate] {
    count += 1
    if count > 1 { throw URLError(.badServerResponse) }
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func finishOldRequest() {
    continuation?.resume(returning: onboardingQuotes())
    continuation = nil
  }
}

private func onboardingQuotes() -> [String: ExchangeRate] {
  Dictionary(
    uniqueKeysWithValues: ["EUR", "USD", "GBP", "JPY", "CZK", "CHF", "PLN", "CAD", "AUD"]
      .enumerated()
      .map { index, code in
        (
          code,
          ExchangeRate(Decimal(index + 1), published: "2026-09-10", source: .init(provider: .ecb))
        )
      })
}

@MainActor
private func waitFor(_ predicate: () -> Bool) async throws {
  for _ in 0..<200 {
    if predicate() { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(predicate(), "Timed out waiting for the first-launch state")
}

@MainActor private final class OnboardingSaveFailure {
  var operation: OnboardingModel.SaveError?
  init(_ operation: OnboardingModel.SaveError?) { self.operation = operation }
}

@Suite @MainActor struct OnboardingTests {
  private func directory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-\(UUID())")
  }

  private func readyModel(at directory: URL) throws -> OnboardingModel {
    try RateCache(directory: directory)
      .save(
        RateSnapshot(quotes: onboardingQuotes(), fetchedAt: .now))
    return OnboardingModel(store: CurrencyStore(directory: directory))
  }

  @Test func fastPartialFiatBecomesReadyAndIsPersistedBeforeCrypto() async throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    let model = OnboardingModel(
      store: store,
      service: RateService(
        fiat: OnboardingProvider(quotes: onboardingQuotes(), delay: .milliseconds(20)),
        daily: OnboardingProvider(delay: .seconds(30)),
        crypto: OnboardingProvider(delay: .seconds(30))))
    #expect(model.phase == .opening)
    model.start()
    try await waitFor { model.phase == .ready }
    #expect(store.loadRates().hasUsablePair(from: "EUR", to: "USD"))
    #expect(model.isRefreshing)
    #expect(model.draft.amount == "100")
    model.pause()
  }

  @Test func slowLoadingAndDeadlineRecoverWithoutWaitingForProvider() async throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let late = LateOnboardingProvider()
    let model = OnboardingModel(
      store: CurrencyStore(directory: location),
      service: RateService(fiat: late, daily: OnboardingProvider(), crypto: nil),
      configuration: .init(loadingDelay: .milliseconds(10), deadline: .milliseconds(100)))
    model.start()
    try await waitFor { model.phase == .waiting }
    try await waitFor { model.phase == .failed }
    #expect(!model.isRefreshing)
    await late.finish()
    try await Task.sleep(for: .milliseconds(30))
    #expect(model.phase == .failed)
    #expect(!model.hasUsableRates)
  }

  @Test func offlineAndServiceFailureRemainDistinct() async throws {
    for (error, phase) in [
      (URLError.Code.notConnectedToInternet, OnboardingModel.Phase.offline),
      (.badServerResponse, .failed)
    ] {
      let location = directory()
      defer { try? FileManager.default.removeItem(at: location) }
      let failure = OnboardingProvider(error: error)
      let model = OnboardingModel(
        store: CurrencyStore(directory: location),
        service: RateService(fiat: failure, daily: failure, crypto: nil))
      model.start()
      try await waitFor { !model.isRefreshing }
      #expect(model.phase == phase)
    }
  }

  @Test func rateSaveFailureRetainsValidWorkAndRetriesOnlyStorage() async throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let failure = OnboardingSaveFailure(.rates)
    let model = OnboardingModel(
      store: CurrencyStore(directory: location),
      service: RateService(
        fiat: OnboardingProvider(quotes: onboardingQuotes()), daily: OnboardingProvider(),
        crypto: nil),
      configuration: .init(beforeSave: { operation in
        if operation == failure.operation { throw CocoaError(.fileWriteOutOfSpace) }
      }))
    model.start()
    try await waitFor { !model.isRefreshing }
    #expect(model.phase == .saveFailed)
    #expect(model.saveError == .rates)
    #expect(!model.hasUsableRates)
    failure.operation = nil
    model.retrySave()
    #expect(model.phase == .ready)
    #expect(model.saveError == nil)
    #expect(!model.isRefreshing)
  }

  @Test func zeroEightAndBaseSwapPreserveOrderedDraft() throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let model = try readyModel(at: location)
    model.continueFromWelcome()
    model.continueFromBaseCurrency()
    model.toggle("USD")
    #expect(model.draft.destinations.isEmpty)
    #expect(!model.canContinue)
    for code in ["USD", "GBP", "JPY", "CZK", "CHF", "PLN", "CAD", "AUD"] { model.toggle(code) }
    #expect(model.draft.destinations.count == 8)
    model.changeBase("GBP")
    #expect(model.draft.source == "GBP")
    #expect(model.draft.destinations == ["USD", "EUR", "JPY", "CZK", "CHF", "PLN", "CAD", "AUD"])
    model.toggle("EUR")
    model.changeBase("EUR")
    #expect(model.draft.destinations == ["USD", "JPY", "CZK", "CHF", "PLN", "CAD", "AUD"])
    model.changeBase("BTC")
    #expect(model.draft.source == "EUR")
    let resumed = OnboardingModel(store: CurrencyStore(directory: location))
    #expect(resumed.step == .selection)
    #expect(resumed.draft == model.draft)
  }

  @Test func selectionAndCompletionFailuresAreSeparateAndRecoverable() throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    _ = try readyModel(at: location)
    let failure = OnboardingSaveFailure(.selection)
    let store = CurrencyStore(directory: location)
    try store.updateInput { $0.setAmount("42") }
    let model = OnboardingModel(
      store: store,
      configuration: .init(beforeSave: {
        if $0 == failure.operation { throw CocoaError(.fileWriteOutOfSpace) }
      }))
    model.continueFromWelcome()
    model.continueFromBaseCurrency()
    model.toggle("GBP")
    model.continueFromSelection()
    #expect(model.step == .selection)
    #expect(model.saveError == .selection)
    #expect(model.draft.destinations == ["USD", "GBP"])
    failure.operation = nil
    model.retrySave()
    #expect(model.step == .homeScreen)
    #expect(!model.complete())
    model.continueFromHomeScreen()
    #expect(model.step == .widgets)
    #expect(store.input().destinations == ["USD", "GBP"])
    #expect(store.input().amount == "42")
    failure.operation = .completion
    #expect(!model.complete())
    #expect(!model.isCompleted)
    #expect(model.step == .widgets)
    #expect(model.saveError == .completion)
    failure.operation = nil
    model.retrySave()
    #expect(model.isCompleted)
    #expect(OnboardingModel(store: store).isCompleted)
  }

  @Test func cachedOldRatesResumeWithoutNetworkAndFutureCacheRecovers() async throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    let old = Date(timeIntervalSince1970: 100)
    try RateCache(directory: location)
      .save(RateSnapshot(quotes: onboardingQuotes(), fetchedAt: old))
    let model = OnboardingModel(store: store)
    #expect(model.phase == .ready)
    #expect(model.lastUpdated == old)
    model.continueFromWelcome()
    model.continueFromBaseCurrency()
    model.toggle("GBP")
    model.pause()
    #expect(OnboardingModel(store: store).draft.destinations == ["USD", "GBP"])
    try RateCache(directory: location)
      .save(
        RateSnapshot(quotes: onboardingQuotes(), fetchedAt: .now.addingTimeInterval(3600)))
    let recovered = OnboardingModel(
      store: store,
      service: RateService(
        fiat: OnboardingProvider(quotes: onboardingQuotes()), daily: OnboardingProvider(),
        crypto: nil))
    #expect(!recovered.hasUsableRates)
    recovered.start()
    try await waitFor { recovered.phase == .ready }
    #expect(store.loadRates().hasValidFetchTimestamp())
  }

  @Test func backgroundCancellationIsNeutralAndResumeRestarts() async throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let model = OnboardingModel(
      store: CurrencyStore(directory: location),
      service: RateService(
        fiat: OnboardingProvider(quotes: onboardingQuotes(), delay: .milliseconds(60)),
        daily: OnboardingProvider(), crypto: nil))
    model.start()
    model.pause()
    // UIKit/SwiftUI commonly reports inactive and then background separately.
    model.pause()
    try await Task.sleep(for: .milliseconds(80))
    #expect(model.phase == .opening)
    #expect(!model.hasUsableRates)
    model.resume()
    try await waitFor { model.phase == .ready }
  }
  @Test func twentyDestinationsStayOrderedAndUnavailableSavedSelectionIsRetained() throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let codes = CurrencyCatalog.codes.sorted().filter { $0 != "EUR" && $0 != "BTC" }.prefix(20)
    var quotes = onboardingQuotes()
    for code in codes {
      quotes[code] = ExchangeRate(2, published: "2026-09-10", source: .init(provider: .ecb))
    }
    let store = CurrencyStore(directory: location)
    try RateCache(directory: location).save(RateSnapshot(quotes: quotes, fetchedAt: .now))
    var draft = ConverterState()
    draft.setDestinations(["BTC"])
    try store.saveOnboardingProgress(OnboardingProgress(draft: draft, step: .selection))
    let model = OnboardingModel(store: store)
    #expect(model.draft.destinations == ["BTC"])
    #expect(!model.canContinue)
    for code in codes { model.toggle(code) }
    #expect(model.draft.destinations == ["BTC"] + codes)
    #expect(model.canContinue)
    model.continueFromSelection()
    #expect(store.input().destinations == ["BTC"] + codes)
    model.back()
    #expect(model.draft.destinations.count == 21)
  }

  @Test func explicitRetryOwnsStateAndIgnoresLateOlderResponse() async throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let provider = RetriedOnboardingProvider()
    let store = CurrencyStore(directory: location)
    let model = OnboardingModel(
      store: store,
      service: RateService(fiat: provider, daily: OnboardingProvider(), crypto: nil),
      configuration: .init(loadingDelay: .milliseconds(5), deadline: .milliseconds(50)))
    model.start()
    // Repeated retries while pending must not create parallel foreground owners.
    model.retry()
    model.retry()
    try await waitFor { model.phase == .failed }
    #expect(await provider.count == 1)
    model.retry()
    try await waitFor { model.phase == .failed && !model.isRefreshing }
    #expect(await provider.count == 2)
    await provider.finishOldRequest()
    try await Task.sleep(for: .milliseconds(30))
    #expect(model.phase == .failed)
    #expect(!model.hasUsableRates)
    #expect(store.loadRates().quotes.isEmpty)
  }

  @Test func corruptCacheAndIdentityOnlyResponseNeverBecomeReady() async throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
    try Data("{broken snapshot}".utf8).write(to: location.appendingPathComponent("rates.json"))
    let model = OnboardingModel(
      store: CurrencyStore(directory: location),
      service: RateService(
        fiat: OnboardingProvider(quotes: [
          "EUR": ExchangeRate(1, published: "2026-09-10", source: .init(provider: .ecb))
        ]), daily: OnboardingProvider(), crypto: nil))
    #expect(!model.hasUsableRates)
    model.start()
    try await waitFor { !model.isRefreshing }
    #expect(model.phase == .failed)
    #expect(!model.hasUsableRates)
    #expect(model.welcomeDestination == nil)
  }

  @Test func failedStageWriteRetriesIntendedNavigationAndCompletedStateCannotReopen() throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    _ = try readyModel(at: location)
    let failure = OnboardingSaveFailure(.draft)
    let model = OnboardingModel(
      store: CurrencyStore(directory: location),
      configuration: .init(beforeSave: { operation in
        if operation == failure.operation { throw CocoaError(.fileWriteOutOfSpace) }
      }))
    model.continueFromWelcome()
    model.continueFromBaseCurrency()
    #expect(model.step == .welcome)
    #expect(model.saveError == .draft)
    failure.operation = nil
    model.retrySave()
    #expect(model.step == .baseCurrency)
    model.continueFromBaseCurrency()
    #expect(model.step == .selection)
    model.continueFromSelection()
    model.continueFromHomeScreen()
    #expect(model.complete())
    model.back()
    model.toggle("GBP")
    #expect(model.step == .widgets)
    #expect(model.draft.destinations == ["USD"])
    #expect(CurrencyStore(directory: location).onboardingProgress()?.completed == true)
  }

  @Test func missingLiveBaseIsUnavailableAndCanRecoverToAnotherBase() async throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    let daily = onboardingQuotes()
    var live = daily
    live["BTC"] = ExchangeRate(
      2, published: "2026-09-10", source: .init(provider: .coinbase), observedAt: .now)
    try RateCache(directory: location)
      .save(
        RateSnapshot(quotes: live, fetchedAt: .now, dailyQuotes: daily))
    var draft = ConverterState()
    draft.changeSource("BTC")
    draft.setDestinations(["EUR", "USD"])
    try store.saveOnboardingProgress(OnboardingProgress(draft: draft, step: .selection))
    let model = OnboardingModel(
      store: store,
      service: RateService(
        fiat: OnboardingProvider(), daily: OnboardingProvider(),
        crypto: OnboardingProvider(error: .badServerResponse)))
    #expect(model.canContinue)
    model.back()
    #expect(model.step == .baseCurrency)
    model.start()
    try await waitFor { !model.isRefreshing }
    #expect(model.hasRecoveryRates)
    #expect(!model.hasUsableRates)
    #expect(model.snapshot.quotes["BTC"] == nil)
    #expect(model.draft.source == "BTC")
    #expect(model.draft.destinations == ["EUR", "USD"])
    #expect(!model.canContinue)
    #expect(model.canUseAsBase("EUR"))
    model.changeBase("EUR")
    #expect(model.canContinue)
    #expect(model.draft.destinations == ["BTC", "USD"])
    #expect(!model.isAvailable("BTC"))
  }

  @Test func savedUnavailableBaseWithCorruptCacheKeepsFiatRecoveryQuotes() async throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    var draft = ConverterState()
    draft.changeSource("BTC")
    draft.setDestinations(["EUR", "USD"])
    try store.saveOnboardingProgress(OnboardingProgress(draft: draft, step: .selection))
    try Data("{corrupt}".utf8).write(to: location.appendingPathComponent("rates.json"))
    let model = OnboardingModel(
      store: store,
      service: RateService(
        fiat: OnboardingProvider(quotes: onboardingQuotes()), daily: OnboardingProvider(),
        crypto: OnboardingProvider(error: .badServerResponse)))
    #expect(!model.canContinue)
    model.start()
    try await waitFor { !model.isRefreshing }
    #expect(model.step == .selection)
    #expect(model.draft.source == "BTC")
    #expect(!model.canContinue)
    #expect(model.snapshot.hasUsablePair(from: "EUR", to: "USD"))
    #expect(store.loadRates().hasUsablePair(from: "EUR", to: "USD"))
    #expect(model.canUseAsBase("EUR"))
    model.changeBase("EUR")
    #expect(model.canContinue)
    #expect(model.phase == .ready)
    #expect(model.draft.destinations == ["BTC", "USD"])
  }

  @Test func savedWelcomeWithUnavailableBaseRetainsExplicitRecoveryRates() async throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    var draft = ConverterState()
    draft.changeSource("BTC")
    draft.setDestinations(["EUR", "USD"])
    try store.saveOnboardingProgress(OnboardingProgress(draft: draft, step: .welcome))
    try Data("{corrupt}".utf8).write(to: location.appendingPathComponent("rates.json"))
    let model = OnboardingModel(
      store: store,
      service: RateService(
        fiat: OnboardingProvider(quotes: onboardingQuotes()), daily: OnboardingProvider(),
        crypto: OnboardingProvider(error: .badServerResponse)))
    #expect(!model.hasRecoveryRates)
    model.start()
    try await waitFor { !model.isRefreshing }
    #expect(model.step == .welcome)
    #expect(model.draft.source == "BTC")
    #expect(model.hasRecoveryRates)
    #expect(!model.hasUsableRates)
    #expect(!model.canContinue)
    #expect(model.canUseAsBase("EUR"))
    #expect(store.loadRates().hasUsablePair(from: "EUR", to: "USD"))
    model.changeBase("EUR")
    #expect(model.hasUsableRates)
    #expect(model.phase == .ready)
    #expect(model.draft.destinations == ["BTC", "USD"])
    model.continueFromWelcome()
    model.continueFromBaseCurrency()
    #expect(model.step == .selection)
  }

  @Test func cachedRatesCanContinueWhenSavingFreshRatesFails() async throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    let savedAt = Date(timeIntervalSince1970: 100)
    let cached = RateSnapshot(quotes: onboardingQuotes(), fetchedAt: savedAt)
    try RateCache(directory: location).save(cached)
    var refreshed = onboardingQuotes()
    refreshed["USD"] = ExchangeRate(
      99, published: "2026-09-10", source: .init(provider: .ecb))
    let model = OnboardingModel(
      store: store,
      service: RateService(
        fiat: OnboardingProvider(quotes: refreshed), daily: OnboardingProvider(), crypto: nil),
      configuration: .init(beforeSave: { operation in
        if operation == .rates { throw CocoaError(.fileWriteOutOfSpace) }
      }))
    model.start()
    try await waitFor { !model.isRefreshing }
    #expect(model.saveError == .rates)
    #expect(model.phase == .ready)
    #expect(model.hasUsableRates)
    #expect(model.snapshot.quotes == cached.quotes)
    #expect(model.lastUpdated == savedAt)
    #expect(store.loadRates().quotes == cached.quotes)
    model.continueFromWelcome()
    model.continueFromBaseCurrency()
    #expect(model.step == .selection)
    #expect(model.snapshot.quotes == cached.quotes)
    #expect(model.lastUpdated == savedAt)
    #expect(store.loadRates().fetchedAt == savedAt)
  }

  @Test func homeScreenStageResumesAndBackNavigationPreservesCommittedChoices() throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    let model = try readyModel(at: location)
    model.continueFromWelcome()
    model.continueFromBaseCurrency()
    model.toggle("GBP")
    model.changeBase("USD")
    model.continueFromSelection()
    #expect(model.step == .homeScreen)
    #expect(store.input().source == "USD")
    #expect(store.input().destinations == ["EUR", "GBP"])
    #expect(!model.complete())
    let resumed = OnboardingModel(store: store)
    #expect(resumed.step == .homeScreen)
    #expect(resumed.draft == model.draft)
    #expect(!resumed.isCompleted)
    resumed.continueFromHomeScreen()
    #expect(resumed.step == .widgets)
    #expect(OnboardingModel(store: store).step == .widgets)
    resumed.back()
    #expect(resumed.step == .homeScreen)
    #expect(OnboardingModel(store: store).step == .homeScreen)
    resumed.back()
    #expect(resumed.step == .selection)
    #expect(resumed.draft == model.draft)
    #expect(store.input().destinations == ["EUR", "GBP"])
  }

  @Test func failedHomeScreenAdvancePreservesStageAndRetriesOnlyProgressSave() throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    _ = try readyModel(at: location)
    let failure = OnboardingSaveFailure(nil)
    let model = OnboardingModel(
      store: store,
      configuration: .init(beforeSave: { operation in
        if operation == failure.operation { throw CocoaError(.fileWriteOutOfSpace) }
      }))
    model.continueFromWelcome()
    model.continueFromBaseCurrency()
    model.toggle("GBP")
    model.continueFromSelection()
    let committed = store.input()
    failure.operation = .draft
    model.continueFromHomeScreen()
    #expect(model.step == .homeScreen)
    #expect(model.saveError == .draft)
    #expect(!model.isCompleted)
    #expect(OnboardingModel(store: store).step == .homeScreen)
    #expect(store.input() == committed)
    failure.operation = nil
    model.retrySave()
    #expect(model.step == .widgets)
    #expect(model.saveError == nil)
    #expect(OnboardingModel(store: store).step == .widgets)
    #expect(store.input() == committed)
    #expect(model.draft.destinations == ["USD", "GBP"])
  }

  @Test func replayUsesCurrentAppChoicesAndPreservesAmountAndRates() throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    let model = try readyModel(at: location)
    model.continueFromWelcome()
    model.continueFromBaseCurrency()
    model.continueFromSelection()
    model.continueFromHomeScreen()
    #expect(model.complete())
    try store.updateInput {
      $0.changeSource("GBP")
      $0.setDestinations(["JPY", "EUR"])
      $0.setAmount("42.75")
    }
    let input = store.input()
    let rates = store.loadRates()
    try model.restart()
    #expect(model.step == .welcome)
    #expect(!model.isCompleted)
    #expect(model.draft.source == "GBP")
    #expect(model.draft.destinations == ["JPY", "EUR"])
    #expect(model.draft.amount == "100")
    #expect(store.input() == input)
    #expect(store.loadRates().quotes == rates.quotes)
    let resumed = OnboardingModel(store: store)
    #expect(!resumed.isCompleted)
    #expect(resumed.step == .welcome)
    #expect(resumed.draft == model.draft)
  }

  @Test func failedReplayKeepsCompletionUntilTheProgressWriteSucceeds() throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    _ = try readyModel(at: location)
    let failure = OnboardingSaveFailure(nil)
    let model = OnboardingModel(
      store: store,
      configuration: .init(beforeSave: {
        if $0 == failure.operation { throw CocoaError(.fileWriteOutOfSpace) }
      }))
    model.continueFromWelcome()
    model.continueFromBaseCurrency()
    model.continueFromSelection()
    model.continueFromHomeScreen()
    #expect(model.complete())
    let input = store.input()
    failure.operation = .draft
    #expect(throws: (any Error).self) { try model.restart() }
    #expect(model.isCompleted)
    #expect(OnboardingModel(store: store).isCompleted)
    #expect(store.input() == input)
    failure.operation = nil
    try model.restart()
    #expect(!model.isCompleted)
    #expect(model.step == .welcome)
  }

  @Test func baseStepResumesWithoutConfirmingAppInputAndCanAdvanceWithNoDestinations() throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    let model = try readyModel(at: location)
    let original = store.input()
    model.continueFromWelcome()
    #expect(model.step == .baseCurrency)
    model.toggle("USD")
    model.changeBase("GBP")
    #expect(model.draft.destinations.isEmpty)
    #expect(!model.canContinue)
    #expect(store.input() == original)
    let resumed = OnboardingModel(store: store)
    #expect(resumed.step == .baseCurrency)
    #expect(resumed.draft.source == "GBP")
    resumed.continueFromBaseCurrency()
    #expect(resumed.step == .selection)
    #expect(resumed.draft.destinations.isEmpty)
    resumed.continueFromSelection()
    #expect(resumed.step == .selection)
    resumed.toggle("EUR")
    resumed.toggle("JPY")
    resumed.back()
    #expect(resumed.step == .baseCurrency)
    resumed.changeBase("EUR")
    #expect(resumed.draft.destinations == ["GBP", "JPY"])
    resumed.continueFromBaseCurrency()
    #expect(resumed.draft.destinations == ["GBP", "JPY"])
    #expect(store.input() == original)
    resumed.continueFromSelection()
    #expect(store.input().source == "EUR")
    #expect(store.input().destinations == ["GBP", "JPY"])
  }

  @Test func baseAdvanceFailureRetainsStepAndRetriesOnlyProgress() throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    let ready = try readyModel(at: location)
    ready.continueFromWelcome()
    let failure = OnboardingSaveFailure(.draft)
    let model = OnboardingModel(
      store: store,
      configuration: .init(beforeSave: {
        if $0 == failure.operation { throw CocoaError(.fileWriteOutOfSpace) }
      }))
    let original = store.input()
    model.continueFromBaseCurrency()
    #expect(model.step == .baseCurrency)
    #expect(model.saveError == .draft)
    #expect(OnboardingModel(store: store).step == .baseCurrency)
    failure.operation = nil
    model.retrySave()
    #expect(model.step == .selection)
    #expect(model.saveError == nil)
    #expect(store.input() == original)
  }

  @Test func existingSelectionRecordStillResumesAndCompletedRecordStaysCompleted() throws {
    let location = directory()
    defer { try? FileManager.default.removeItem(at: location) }
    let store = CurrencyStore(directory: location)
    let ready = try readyModel(at: location)
    var draft = ready.draft
    draft.changeSource("GBP")
    draft.setDestinations(["JPY", "USD"])
    // Version 1 and the original raw "selection" identifier remain compatible.
    let progress = OnboardingProgress(version: 1, draft: draft, step: .selection)
    let data = try JSONEncoder().encode(progress)
    #expect(String(decoding: data, as: UTF8.self).contains("\"selection\""))
    try data.write(to: location.appendingPathComponent("onboarding.json"))
    let resumed = OnboardingModel(store: store)
    #expect(resumed.step == .selection)
    #expect(resumed.draft == draft)
    resumed.back()
    #expect(resumed.step == .baseCurrency)
    #expect(resumed.draft == draft)
    resumed.back()
    #expect(resumed.step == .welcome)
    try store.saveOnboardingProgress(
      OnboardingProgress(version: 1, draft: draft, step: .widgets, completed: true))
    #expect(OnboardingModel(store: store).isCompleted)
  }

}
