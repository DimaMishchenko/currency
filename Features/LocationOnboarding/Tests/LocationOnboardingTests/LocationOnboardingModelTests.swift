import Foundation
import LocalCurrency
import LocationOnboarding
import Testing

@MainActor @Suite struct LocationOnboardingModelTests {
  @Test func completionRequiresFreshResultAndSavesBeforeOutput() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var snapshot = LocationSnapshot(
      phase: .ready,
      resolved: WidgetLocation(
        country: "CZ", currency: "CZK", updatedAt: now.addingTimeInterval(-90000)))
    var failing = true
    var saved = false
    var outputs = 0
    var cancellations = 0
    let model = LocationOnboardingModel(
      dependencies: LocationOnboardingDependencies(
        readSnapshot: { snapshot }, reconcile: {}, update: { _ in }, cancel: { cancellations += 1 },
        addResolvedCurrency: {
          if failing { throw CocoaError(.fileWriteUnknown) }
          saved = true
        }, now: { now },
        output: { _ in
          #expect(saved); outputs += 1
        }), addsResolvedCurrencyToApp: true)
    #expect(!model.complete())
    #expect(outputs == 0)
    snapshot.resolved = WidgetLocation(country: "CZ", currency: "CZK", updatedAt: now)
    #expect(!model.complete())
    #expect(model.saveFailed)
    #expect(!model.stopped)
    failing = false
    #expect(model.complete())
    #expect(outputs == 1)
    #expect(cancellations == 1)
    model.stop()
    #expect(cancellations == 1)
  }
  @Test func foregroundReconcileDoesNotPromptAndRepeatedUpdatesAreIgnored() {
    var snapshot = LocationSnapshot(permissionAuthorized: true)
    var permissionRequests: [Bool] = []
    var reconciliations = 0
    let model = LocationOnboardingModel(
      dependencies: LocationOnboardingDependencies(
        readSnapshot: { snapshot }, reconcile: { reconciliations += 1 },
        update: {
          permissionRequests.append($0); snapshot.isUpdating = true
        }, cancel: {},
        addResolvedCurrency: {}, now: { .now }, output: { _ in }))
    model.refreshLocation()
    model.update()
    #expect(permissionRequests == [false])
    #expect(reconciliations == 1)
    model.stop()
    model.refreshLocation()
    #expect(reconciliations == 1)
  }
}
