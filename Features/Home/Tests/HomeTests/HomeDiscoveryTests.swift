import Conversion
import ExchangeRates
import Foundation
import Home
import Testing

@MainActor
struct HomeDiscoveryTests {
  private let firstDay = Date(timeIntervalSince1970: 1_780_000_000)

  @Test func policyRequiresLaterDayUsefulEditAndNoPriorDiscovery() {
    var progress = HomeDiscoveryProgress()
    progress.firstObservedAt = firstDay
    progress.completedEdits = 1
    let later = firstDay.addingTimeInterval(86_400)
    #expect(progress.canOfferHistory(editing: true))
    #expect(!progress.canOfferHistory(editing: false))
    #expect(
      !progress.canOfferWidgets(
        now: firstDay, closedWithResults: true, firstHomeVisit: false,
        historyShownThisVisit: false))
    #expect(
      !progress.canOfferWidgets(
        now: later, closedWithResults: false, firstHomeVisit: false,
        historyShownThisVisit: false))
    #expect(
      !progress.canOfferWidgets(
        now: later, closedWithResults: true, firstHomeVisit: true,
        historyShownThisVisit: false))
    #expect(
      !progress.canOfferWidgets(
        now: later, closedWithResults: true, firstHomeVisit: false,
        historyShownThisVisit: true))
    #expect(
      progress.canOfferWidgets(
        now: later, closedWithResults: true, firstHomeVisit: false,
        historyShownThisVisit: false))
    progress.visitedDetails = true
    progress.openedWidgets = true
    #expect(!progress.canOfferHistory(editing: true))
    #expect(
      !progress.canOfferWidgets(
        now: later, closedWithResults: true, firstHomeVisit: false,
        historyShownThisVisit: false))
  }

  @Test func progressPersistsAcrossStoreInstances() throws {
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var progress = HomeDiscoveryProgress()
    progress.firstObservedAt = firstDay
    progress.completedEdits = 2
    progress.showedHistoryTip = true
    progress.showedWidgetsTip = true
    HomeDiscoveryStore(defaults: defaults).save(progress)
    #expect(HomeDiscoveryStore(defaults: defaults).load() == progress)
  }

  @Test func finalAmountAndAvailableResultsControlSessionLearning() throws {
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let discovery = HomeDiscoveryStore(defaults: defaults)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var now = firstDay
    let rates = RateSnapshot(quotes: [
      "EUR": ExchangeRate(1, published: "2026-09-28", source: .init(provider: .ecb)),
      "USD": ExchangeRate(2, published: "2026-09-28", source: .init(provider: .ecb))
    ])
    let model = makeHomeModel(
      store: HomeTestStore(directory: directory), service: RateService(),
      readRates: { rates }, discovery: discovery, now: { now })
    let firstVisit = UUID()
    model.beginDiscoveryVisit(id: firstVisit)
    #expect(discovery.load().firstObservedAt == firstDay)
    model.beginEditing("EUR")
    model.offerHistoryTip()
    #expect(model.activeDiscoveryTip == nil)
    #expect(model.press("1"))
    model.endEditing()
    #expect(discovery.load().completedEdits == 0)
    model.beginEditing("EUR")
    #expect(model.press("2"))
    #expect(model.press("⌫"))
    #expect(model.press("1"))
    model.endEditing()
    #expect(discovery.load().completedEdits == 0)
    model.beginEditing("EUR")
    #expect(model.press("5"))
    model.endEditing()
    #expect(discovery.load().completedEdits == 1)
    model.offerWidgetsTip()
    #expect(model.activeDiscoveryTip == nil)

    now.addTimeInterval(86_400)
    model.endDiscoveryVisit()
    let secondVisit = UUID()
    model.beginDiscoveryVisit(id: secondVisit)
    model.beginEditing("EUR")
    model.offerHistoryTip()
    #expect(model.activeDiscoveryTip == .history)
    model.discoveryTipPresented(.history)
    #expect(discovery.load().showedHistoryTip)
    #expect(model.press("6"))
    model.endEditing()
    model.offerWidgetsTip()
    #expect(model.activeDiscoveryTip == nil)

    model.endDiscoveryVisit()
    model.beginDiscoveryVisit(id: secondVisit)
    model.beginEditing("EUR")
    #expect(model.press("8"))
    model.endEditing()
    model.offerWidgetsTip()
    #expect(model.activeDiscoveryTip == nil)

    model.endDiscoveryVisit()
    model.beginDiscoveryVisit(id: UUID())
    model.beginEditing("EUR")
    #expect(model.press("7"))
    model.endEditing()
    model.offerWidgetsTip()
    #expect(model.activeDiscoveryTip == .widgets)
    model.discoveryTipPresented(.widgets)
    #expect(discovery.load().showedWidgetsTip)
    model.endDiscoveryTip(.widgets)
    model.offerWidgetsTip()
    #expect(model.activeDiscoveryTip == nil)
    model.visitWidgets()
    #expect(discovery.load().openedWidgets)
  }

  @Test func firstHomeVisitAfterOnboardingExcludesWidgetsEvenOnLaterDay() throws {
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let discovery = HomeDiscoveryStore(defaults: defaults)
    var progress = HomeDiscoveryProgress()
    progress.firstObservedAt = firstDay
    discovery.save(progress)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var completed = false
    let later = firstDay.addingTimeInterval(86_400)
    let model = makeHomeModel(
      store: HomeTestStore(directory: directory), service: RateService(),
      readRates: {
        RateSnapshot(quotes: [
          "EUR": ExchangeRate(1, published: "2026-09-28", source: .init(provider: .ecb)),
          "USD": ExchangeRate(2, published: "2026-09-28", source: .init(provider: .ecb))
        ])
      }, discovery: discovery, onboardingCompleted: { completed }, now: { later })
    completed = true
    model.beginDiscoveryVisit(id: UUID())
    model.beginEditing("EUR")
    #expect(model.press("8"))
    model.endEditing()
    model.offerWidgetsTip()
    #expect(model.activeDiscoveryTip == nil)
    model.endDiscoveryVisit()
    model.beginDiscoveryVisit(id: UUID())
    model.beginEditing("EUR")
    #expect(model.press("9"))
    model.endEditing()
    model.offerWidgetsTip()
    #expect(model.activeDiscoveryTip == .widgets)
  }

  @Test func missingConversionResultsDoNotOfferWidgets() throws {
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let discovery = HomeDiscoveryStore(defaults: defaults)
    var progress = HomeDiscoveryProgress()
    progress.firstObservedAt = firstDay
    discovery.save(progress)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let later = firstDay.addingTimeInterval(86_400)
    let model = makeHomeModel(
      store: HomeTestStore(directory: directory), service: RateService(),
      readRates: { RateSnapshot() }, discovery: discovery, now: { later })
    model.beginDiscoveryVisit(id: UUID())
    model.beginEditing("EUR")
    #expect(model.press("4"))
    model.endEditing()
    model.offerWidgetsTip()
    #expect(discovery.load().completedEdits == 1)
    #expect(model.activeDiscoveryTip == nil)
  }
}
