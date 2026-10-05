import CompanionSync
import Conversion
import ExchangeRates
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
  @Test func legacyContextDefaultsToTroyOunces() throws {
    let context = try JSONDecoder()
      .decode(
        CompanionFavoritesContext.self,
        from: Data(
          #"{"schemaVersion":1,"senderID":"00000000-0000-0000-0000-000000000001","revision":7,"codes":["EUR","XAU"]}"#
            .utf8))
    try context.validate()
    #expect(context.metalUnit == .troyOunce)
    let fixture = SyncFixture()
    var state = CompanionSyncState(senderID: context.senderID)
    state.outgoing = context
    fixture.saved = state
    fixture.input.setDestinations(["XAU"])
    #expect(try fixture.engine().phoneContext(for: fixture.input).revision == 7)
    fixture.input.changeSource("XAU")
    fixture.input.setMetalUnit(.gram)
    fixture.input.setAmount("31.1034768")
    #expect(try fixture.engine().accept(context))
    #expect(fixture.input.source == "XAU")
    #expect(fixture.input.metalUnit == .troyOunce)
    #expect(fixture.input.decimal == 1)
  }

  @Test func metalUnitOnlyChangeRevisesPhoneContextAndSurvivesRestart() throws {
    let fixture = SyncFixture()
    let engine = try fixture.engine()
    let first = try engine.phoneContext(for: fixture.input)
    fixture.input.setMetalUnit(.gram)
    let second = try engine.phoneContext(for: fixture.input)
    #expect(second.codes == first.codes)
    #expect(second.senderID == first.senderID)
    #expect(second.revision == first.revision + 1)
    #expect(second.metalUnit == .gram)
    let decoded = try JSONDecoder()
      .decode(
        CompanionFavoritesContext.self, from: JSONEncoder().encode(second))
    #expect(decoded == second)
    #expect(try fixture.engine().phoneContext(for: fixture.input) == second)
    fixture.input.setAmount("99")
    #expect(try engine.phoneContext(for: fixture.input) == second)
  }

  @Test(arguments: ["XAU", "XAG", "XPT", "XPD"])
  func acceptedMetalUnitPreservesWatchSourceMass(_ source: String) throws {
    let fixture = SyncFixture()
    fixture.input.changeSource(source)
    fixture.input.setAmount("2")
    let engine = try fixture.engine()
    let sender = UUID()
    let grams = CompanionFavoritesContext(
      senderID: sender, revision: 1, codes: ["EUR", "USD"], metalUnit: .gram)
    #expect(try engine.accept(grams))
    #expect(fixture.input.source == source)
    #expect(fixture.input.metalUnit == .gram)
    #expect(fixture.input.decimal == 2 * MetalUnit.troyOunce.gramsPerUnit)
    let kilograms = CompanionFavoritesContext(
      senderID: sender, revision: 2, codes: grams.codes, metalUnit: .kilogram)
    #expect(try engine.accept(kilograms))
    #expect(fixture.input.source == source)
    #expect(fixture.input.metalUnit == .kilogram)
    #expect(fixture.input.decimal == 2 * MetalUnit.troyOunce.gramsPerUnit / 1000)
  }

  @Test(arguments: ["GBP", "BTC"])
  func acceptedMetalUnitPreservesNonmetalWatchAmount(_ source: String) throws {
    let fixture = SyncFixture()
    fixture.input.changeSource(source)
    fixture.input.setAmount("12.50")
    let context = CompanionFavoritesContext(
      senderID: UUID(), revision: 1, codes: ["EUR", "XAU"], metalUnit: .kilogram)
    #expect(try fixture.engine().accept(context))
    #expect(fixture.input.source == source)
    #expect(fixture.input.amount == "12.50")
    #expect(fixture.input.metalUnit == .kilogram)
  }

  @Test func metadataRetryDoesNotConvertMetalSourceTwice() throws {
    let fixture = SyncFixture()
    fixture.input.changeSource("XAU")
    let engine = try fixture.engine()
    let context = CompanionFavoritesContext(
      senderID: UUID(), revision: 1, codes: ["EUR", "USD"], metalUnit: .gram)
    fixture.failMetadata = true
    #expect(throws: SyncFixture.Failure.metadata) { try engine.accept(context) }
    #expect(fixture.input.decimal == MetalUnit.troyOunce.gramsPerUnit)
    fixture.failMetadata = false
    #expect(try engine.accept(context))
    #expect(fixture.input.decimal == MetalUnit.troyOunce.gramsPerUnit)
    #expect(try !engine.accept(context))
  }

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
    let newest = CompanionFavoritesContext(
      senderID: sender, revision: 3, codes: ["EUR", "CZK"], metalUnit: .gram)
    #expect(try engine.accept(newest))
    fixture.input.setAmount("100")
    let older = CompanionFavoritesContext(
      senderID: sender, revision: 2, codes: ["EUR", "JPY"], metalUnit: .kilogram)
    #expect(try !engine.accept(older))
    #expect(try !fixture.engine().accept(newest))
    #expect(fixture.input.amount == "100")
    #expect(fixture.input.manualDestinations == ["CZK"])
    #expect(fixture.input.metalUnit == .gram)
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
