import CoreSpotlight
import ExchangeRates
import Foundation
import LocalCurrency
import Testing

@MainActor @Suite struct CurrencySearchIndexTests {
  @Test func upgradePreservesNamedIndexAndOnlyCleansLegacyDomain() {
    #expect(CurrencySearchIndex.indexName == "Currency.SelectedCurrencies")
    #expect(CurrencySearchIndex.cleanupDomains == ["Currency.SelectedCurrencies"])
  }
  @Test func localItemIdentifierSurvivesPermissionChanges() {
    let resolved = CurrencyEntity(
      "@local", local: .init(country: "CZ", currency: "CZK"))
    let unavailable = CurrencyEntity("@local")
    #expect(
      CSSearchableItem(appEntity: resolved).uniqueIdentifier
        == CSSearchableItem(appEntity: unavailable).uniqueIdentifier)
  }
  @Test func fullCatalogReconciliationPublishesEverySupportedCode() async {
    let state = CurrencySearchIndex.State(
      ids: CurrencyCatalog.codes, observation: nil, status: .denied)
    var published: [CurrencyEntity] = []
    let index = CurrencySearchIndex(
      dependencies: .init(
        readState: { state }, delete: {}, publish: { published = $0 }))
    await index.rebuild()
    #expect(Set(published.map(\.id)) == Set(CurrencyCatalog.codes))
  }
  @Test func unchangedOrdinaryReconciliationSkipsWorkButSystemAndLocaleRebuild() async {
    var state = CurrencySearchIndex.State(ids: ["EUR"], observation: nil, status: .denied)
    var deletes = 0
    var publications = 0
    let index = CurrencySearchIndex(
      dependencies: .init(
        readState: { state }, delete: { deletes += 1 }, publish: { _ in publications += 1 }))
    await index.rebuild()
    await withCheckedContinuation { continuation in
      index.reconcile { continuation.resume() }
    }
    #expect(deletes == 1 && publications == 1)
    await index.rebuild()
    #expect(deletes == 2 && publications == 2)
    state.localeIdentifier = "uk_UA"
    await withCheckedContinuation { continuation in
      index.reconcile { continuation.resume() }
    }
    #expect(deletes == 3 && publications == 3)
  }
  @Test func revokedLocalDuringDeletionCannotRepublishOldMetadata() async {
    var state = CurrencySearchIndex.State(
      ids: ["EUR", "@local"], observation: .init(country: "CZ", currency: "CZK"), status: .available
    )
    var published: [[CurrencyEntity]] = []
    let index = CurrencySearchIndex(
      dependencies: .init(
        readState: { state }, delete: { state.status = .denied }, publish: { published.append($0) })
    )
    await index.rebuild()
    #expect(published.count == 1)
    #expect(published[0].map(\.id) == ["EUR"])
    #expect(!index.cleanupNeeded)
  }
  @Test func selectionChangedDuringPublicationConvergesBeforeAcknowledging() async {
    var state = CurrencySearchIndex.State(
      ids: ["EUR", "@local"], observation: .init(country: "CZ", currency: "CZK"), status: .available
    )
    var published: [[CurrencyEntity]] = []
    var deletes = 0
    let index = CurrencySearchIndex(
      dependencies: .init(
        readState: { state }, delete: { deletes += 1 },
        publish: { entities in
          published.append(entities)
          state.ids = ["EUR"]
        }))
    await index.rebuild()
    #expect(deletes == 2)
    #expect(published.last?.map(\.id) == ["EUR"])
    #expect(!index.cleanupNeeded)
  }
  @Test func failedCleanupRemainsPendingAndNextReconciliationRetries() async {
    let state = CurrencySearchIndex.State(ids: ["EUR"], observation: nil, status: .denied)
    var attempts = 0
    var published: [[CurrencyEntity]] = []
    let index = CurrencySearchIndex(
      dependencies: .init(
        readState: { state },
        delete: {
          attempts += 1
          if attempts == 1 { throw CocoaError(.fileWriteNoPermission) }
        }, publish: { published.append($0) }))
    await index.rebuild()
    #expect(index.cleanupNeeded && published.isEmpty)
    await index.rebuild()
    #expect(attempts == 2 && !index.cleanupNeeded)
    #expect(published.last?.map(\.id) == ["EUR"])
  }
}
