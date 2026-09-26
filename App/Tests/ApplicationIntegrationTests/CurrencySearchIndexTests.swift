import Foundation
import LocalCurrency
import Testing

@MainActor @Suite struct CurrencySearchIndexTests {
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
    #expect(published[0].last?.id == "@local")
    #expect(published[0].last?.resolvedLocalCode == nil)
    #expect(published[0].last?.localCountry == nil)
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
