import Conversion
import ExchangeRates
import Foundation
import Home
import Testing

@MainActor
struct HomeReviewTests {
  @Test func sharedWidgetUsageAndAppCompletionReachThreeAndReset() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let usage = ConversionUsageStore(directory: directory)
    let store = HomeTestStore(directory: directory)
    try store.updateInput { $0.setDestinations(["USD"]) }
    let now = Date(timeIntervalSince1970: 1_000)
    try usage.recordWidgetConversion(key: "calculator", now: now)
    try usage.recordWidgetConversion(key: "calculator", now: now.addingTimeInterval(40))
    let model = makeHomeModel(
      store: store, service: RateService(), readRates: { Self.rates },
      recordConversion: { try? usage.recordConversion() },
      claimReviewRequest: { (try? usage.claimReviewRequest()) ?? false })
    #expect(!model.canRequestReview)
    model.beginEditing("EUR")
    #expect(model.press("4"))
    #expect(!model.claimReviewRequest())
    model.endEditing()
    #expect(model.canRequestReview)
    #expect(model.claimReviewRequest())
    #expect(!model.claimReviewRequest())
    #expect(try !usage.claimReviewRequest())
  }

  @Test func unchangedZeroUnavailableAndOnboardingEditsDoNotCount() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HomeTestStore(directory: directory)
    try store.updateInput { $0.setDestinations(["USD"]) }
    var completed = 0
    var onboarded = false
    var snapshot = Self.rates
    let model = makeHomeModel(
      store: store, service: RateService(), readRates: { snapshot },
      onboardingCompleted: { onboarded }, recordConversion: { completed += 1 })
    model.beginEditing("EUR")
    #expect(model.press("4"))
    model.endEditing()
    #expect(completed == 0)
    onboarded = true
    model.beginEditing("EUR")
    model.endEditing()
    #expect(completed == 0)
    model.beginEditing("EUR")
    #expect(model.press("AC"))
    model.endEditing()
    #expect(completed == 0)
    snapshot = RateSnapshot()
    model.reloadSharedState()
    model.beginEditing("EUR")
    model.endEditing()
    #expect(completed == 0)
    #expect(!model.canRequestReview)
  }

  @Test func anotherEditOrPresentedFlowCancelsTheOpportunity() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HomeTestStore(directory: directory)
    try store.updateInput { $0.setDestinations(["USD"]) }
    var claims = 0
    let model = makeHomeModel(
      store: store, service: RateService(), readRates: { Self.rates },
      claimReviewRequest: {
        claims += 1; return true
      })
    model.beginEditing("EUR")
    #expect(model.press("4"))
    model.endEditing()
    #expect(model.canRequestReview)
    model.beginEditing("EUR")
    #expect(!model.canRequestReview)
    #expect(!model.claimReviewRequest())
    #expect(model.press("2"))
    model.endEditing()
    model.cancelReviewOpportunity()
    #expect(!model.claimReviewRequest())
    #expect(claims == 0)
  }

  @Test func discoveryPresentationDefersReviewUntilAnotherVisit() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let discovery = HomeDiscoveryStore(defaults: defaults)
    var progress = HomeDiscoveryProgress()
    progress.completedEdits = 1
    discovery.save(progress)
    let store = HomeTestStore(directory: directory)
    try store.updateInput { $0.setDestinations(["USD"]) }
    let model = makeHomeModel(
      store: store, service: RateService(), readRates: { Self.rates },
      discovery: discovery, claimReviewRequest: { true })
    model.beginDiscoveryVisit(id: UUID())
    model.beginEditing("EUR")
    model.offerHistoryTip()
    model.discoveryTipPresented(.history)
    #expect(model.press("4"))
    model.endEditing()
    #expect(!model.claimReviewRequest())
    model.beginDiscoveryVisit(id: UUID())
    model.beginEditing("EUR")
    #expect(model.press("2"))
    model.endEditing()
    #expect(model.claimReviewRequest())
  }

  @Test func refreshCancelsPendingReviewUntilAnotherConversion() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var input = ConverterState()
    input.setDestinations(["USD"])
    let model = HomeModel(
      dependencies: HomeDependencies(
        readInput: { input }, readRates: { Self.rates }, readRateIssue: { nil },
        readLocalCurrency: { (nil, .notDetermined) },
        editInput: { mutation in
          try mutation(&input); return input
        },
        refreshRates: { _ in RefreshResult(snapshot: Self.rates, warning: nil) },
        changes: { AsyncStream { $0.finish() } }, readDiscovery: { HomeDiscoveryProgress() },
        saveDiscovery: { _ in }, onboardingCompleted: { true }, recordConversion: {},
        claimReviewRequest: { true }, now: { .now }))
    model.beginEditing("EUR")
    #expect(model.press("4"))
    model.endEditing()
    #expect(model.canRequestReview)
    #expect(await model.refresh() == .refreshed)
    #expect(!model.claimReviewRequest())
    model.beginEditing("EUR")
    #expect(model.press("2"))
    model.endEditing()
    #expect(model.claimReviewRequest())
  }

  private static var rates: RateSnapshot {
    RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-10-25", source: .init(provider: .custom("test"))),
      "USD": ExchangeRate(2, published: "2026-10-25", source: .init(provider: .custom("test")))
    ])
  }
}
