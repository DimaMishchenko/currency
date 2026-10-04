import CompanionSync
import Conversion
import Foundation
import Testing

@MainActor
private final class SyncFixture {
  var saved: CompanionSyncState?
  var input = ConverterState()
  var notifications = 0
  var failMetadata = false
  var failInput = false
  enum Failure: Error, Equatable { case metadata, input }

  func engine() throws -> CompanionSyncEngine {
    try CompanionSyncEngine(
      dependencies: .init(
        loadState: { self.saved },
        saveState: {
          if self.failMetadata { throw Failure.metadata }
          self.saved = $0
        },
        editInput: {
          if self.failInput { throw Failure.input }
          var next = self.input
          try $0(&next)
          self.input = next
        },
        changed: { self.notifications += 1 }))
  }
}

@Suite @MainActor
struct CompanionSyncTests {
  @Test func phoneRevisionsTrackFavoritesAndSurviveRestart() throws {
    let fixture = SyncFixture()
    let engine = try fixture.engine()
    let first = try engine.phoneContext(for: fixture.input)
    #expect(first.codes == [fixture.input.source] + fixture.input.manualDestinations)
    #expect(first.revision == 1)
    fixture.input.setAmount("9.25")
    #expect(try engine.phoneContext(for: fixture.input) == first)
    fixture.input.setDestinations(["CZK", "USD"])
    let second = try engine.phoneContext(for: fixture.input)
    #expect(second.senderID == first.senderID)
    #expect(second.revision == 2)
    #expect(try fixture.engine().phoneContext(for: fixture.input) == second)
  }

  @Test func watchPreservesAmountSourceAndCurrentPair() throws {
    let fixture = SyncFixture()
    fixture.input.changeSource("GBP")
    fixture.input.setDestinations(["CZK", "USD"])
    fixture.input.setAmount("12.50")
    let engine = try fixture.engine()
    let context = CompanionFavoritesContext(
      senderID: UUID(), revision: 2, codes: ["EUR", "USD", "CZK"])
    #expect(try engine.accept(context))
    #expect(fixture.input.source == "GBP")
    #expect(fixture.input.amount == "12.50")
    #expect(fixture.input.primaryDestination == "CZK")
    #expect(fixture.input.manualDestinations == ["CZK", "EUR", "USD"])
    #expect(fixture.notifications == 1)
  }

  @Test func duplicateAndOlderContextsDoNotOverwriteNewerPreferences() throws {
    let fixture = SyncFixture()
    let sender = UUID()
    let engine = try fixture.engine()
    let newest = CompanionFavoritesContext(senderID: sender, revision: 3, codes: ["EUR", "CZK"])
    #expect(try engine.accept(newest))
    fixture.input.setAmount("100")
    let older = CompanionFavoritesContext(senderID: sender, revision: 2, codes: ["EUR", "JPY"])
    #expect(try !engine.accept(older))
    #expect(try !fixture.engine().accept(newest))
    #expect(fixture.input.amount == "100")
    #expect(fixture.input.manualDestinations == ["CZK"])
    #expect(fixture.notifications == 1)
  }

  @Test func invalidPayloadsNeverMutateInput() throws {
    let fixture = SyncFixture()
    let engine = try fixture.engine()
    for context in [
      CompanionFavoritesContext(schemaVersion: 2, senderID: UUID(), revision: 1, codes: ["EUR"]),
      CompanionFavoritesContext(senderID: UUID(), revision: 0, codes: ["EUR"]),
      CompanionFavoritesContext(senderID: UUID(), revision: 1, codes: ["ZZZ"]),
      CompanionFavoritesContext(senderID: UUID(), revision: 1, codes: ["EUR", "EUR"]),
      CompanionFavoritesContext(senderID: UUID(), revision: 1, codes: [])
    ] {
      #expect(throws: CompanionSyncError.invalidContext) { try engine.accept(context) }
    }
    #expect(fixture.input == ConverterState())
    #expect(fixture.notifications == 0)
  }

  @Test func inputFailureDoesNotAcknowledgeRevision() throws {
    let fixture = SyncFixture()
    let engine = try fixture.engine()
    let context = CompanionFavoritesContext(senderID: UUID(), revision: 1, codes: ["EUR", "JPY"])
    fixture.failInput = true
    #expect(throws: SyncFixture.Failure.input) { try engine.accept(context) }
    #expect(fixture.saved == nil)
    #expect(fixture.notifications == 0)
    fixture.failInput = false
    #expect(try engine.accept(context))
    #expect(try !engine.accept(context))
    #expect(fixture.notifications == 1)
  }

  @Test func metadataFailureCanRetryWithoutLosingWatchInput() throws {
    let fixture = SyncFixture()
    fixture.input.setAmount("42")
    let engine = try fixture.engine()
    let context = CompanionFavoritesContext(senderID: UUID(), revision: 1, codes: ["EUR", "JPY"])
    fixture.failMetadata = true
    #expect(throws: SyncFixture.Failure.metadata) { try engine.accept(context) }
    #expect(fixture.saved == nil)
    #expect(fixture.input.amount == "42")
    fixture.input.setAmount("100")
    fixture.input.changeSource("GBP")
    fixture.failMetadata = false
    #expect(try engine.accept(context))
    #expect(fixture.input.amount == "100")
    #expect(fixture.input.source == "GBP")
    #expect(fixture.input.primaryDestination == "JPY")
    #expect(fixture.input.manualDestinations == ["JPY", "EUR"])
    #expect(try !engine.accept(context))
    #expect(fixture.notifications == 2)
  }

  @Test func failedPhonePersistenceDoesNotAdvancePublication() throws {
    let fixture = SyncFixture()
    let engine = try fixture.engine()
    fixture.failMetadata = true
    #expect(throws: SyncFixture.Failure.metadata) { try engine.phoneContext(for: fixture.input) }
    #expect(engine.outgoing == nil)
    fixture.failMetadata = false
    #expect(try engine.phoneContext(for: fixture.input).revision == 1)
  }

  @Test func localStateStoreRetainsInvalidRecords() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CompanionSyncStateStore(directory: directory)
    #expect(try store.load() == nil)
    let state = CompanionSyncState()
    try store.save(state)
    #expect(try store.load() == state)
    let record = directory.appendingPathComponent("companion-sync.json")
    try Data("invalid".utf8).write(to: record)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try Data(contentsOf: record) == Data("invalid".utf8))
  }
}
