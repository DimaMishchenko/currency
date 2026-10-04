import Conversion
import ExchangeRates
import Foundation

/// Versioned phone-owned favorites, excluding transient conversion and location state.
public struct CompanionFavoritesContext: Codable, Sendable, Equatable {
  /// The supported payload version.
  public let schemaVersion: Int
  /// Stable identity of one phone installation's revision history.
  public let senderID: UUID
  /// Monotonically increasing preference revision for this sender.
  public let revision: UInt64
  /// Ordered favorite codes, including the phone's source currency.
  public let codes: [String]

  /// Explicit schema and revision values permit validation before accepting transported data.
  public init(schemaVersion: Int = 1, senderID: UUID, revision: UInt64, codes: [String]) {
    self.schemaVersion = schemaVersion
    self.senderID = senderID
    self.revision = revision
    self.codes = codes
  }

  /// Rejects unsupported versions, invalid revisions, and malformed currency selections.
  public func validate() throws {
    guard schemaVersion == 1, revision > 0, !codes.isEmpty,
      codes.count <= CurrencyCatalog.codes.count,
      Set(codes).count == codes.count,
      codes.allSatisfy({ CurrencyCatalog.codes.contains($0) })
    else { throw CompanionSyncError.invalidContext }
  }
}

/// Durable revision metadata independent of converter edit timestamps.
public struct CompanionSyncState: Codable, Sendable, Equatable {
  /// Stable identity used for phone publications.
  public let senderID: UUID
  /// Latest published phone preferences, retained for activation retries.
  public var outgoing: CompanionFavoritesContext?
  /// Last committed revision received from each sender.
  public var acceptedRevisions: [UUID: UInt64]

  /// A new installation begins without published or received revisions.
  public init(senderID: UUID = UUID()) {
    self.senderID = senderID
    outgoing = nil
    acceptedRevisions = [:]
  }
}

/// Typed payload and revision failures; injected storage failures propagate unchanged.
public enum CompanionSyncError: Error, Equatable {
  case invalidContext, revisionExhausted
}

/// Explicit persistence and confirmed-input operations supplied by the executable.
@MainActor
public struct CompanionSyncDependencies {
  /// Loads revision metadata; only an absent record should return nil.
  public var loadState: () throws -> CompanionSyncState?
  /// Atomically saves revision metadata.
  public var saveState: (CompanionSyncState) throws -> Void
  /// Mutates the freshest confirmed Watch input.
  public var editInput: ((inout ConverterState) throws -> Void) throws -> Void
  /// Publishes a successfully committed Watch preference change to local observers.
  public var changed: () -> Void

  /// Storage commits may throw; successful input commits notify local consumers before metadata acknowledgement.
  public init(
    loadState: @escaping () throws -> CompanionSyncState?,
    saveState: @escaping (CompanionSyncState) throws -> Void,
    editInput: @escaping ((inout ConverterState) throws -> Void) throws -> Void,
    changed: @escaping () -> Void
  ) {
    self.loadState = loadState
    self.saveState = saveState
    self.editInput = editInput
    self.changed = changed
  }
}

/// Owns favorite revisions and acceptance; transport activation is a separate lifetime.
@MainActor
public final class CompanionSyncEngine {
  private let dependencies: CompanionSyncDependencies
  private var state: CompanionSyncState

  /// Restores revision metadata without starting WatchConnectivity.
  public init(dependencies: CompanionSyncDependencies) throws {
    self.dependencies = dependencies
    state = try dependencies.loadState() ?? CompanionSyncState()
    if let outgoing = state.outgoing {
      try outgoing.validate()
      guard outgoing.senderID == state.senderID else { throw CompanionSyncError.invalidContext }
    }
  }

  /// Latest durable publication available for activation or reachability-independent retries.
  public var outgoing: CompanionFavoritesContext? { state.outgoing }

  /// Revises only changed phone favorites and persists before publication.
  public func phoneContext(for input: ConverterState) throws -> CompanionFavoritesContext {
    let codes = [input.source] + input.manualDestinations
    if let outgoing = state.outgoing, outgoing.codes == codes { return outgoing }
    let revision = state.outgoing?.revision ?? 0
    guard revision < UInt64.max else { throw CompanionSyncError.revisionExhausted }
    let context = CompanionFavoritesContext(
      senderID: state.senderID, revision: revision + 1, codes: codes)
    try context.validate()
    var next = state
    next.outgoing = context
    try dependencies.saveState(next)
    state = next
    return context
  }

  /// Accepts a newer context while preserving Watch amount, source, and available selected pair.
  @discardableResult
  public func accept(_ context: CompanionFavoritesContext) throws -> Bool {
    try context.validate()
    guard context.revision > (state.acceptedRevisions[context.senderID] ?? 0) else { return false }
    try dependencies.editInput { input in
      var destinations = context.codes.filter { $0 != input.source }
      if let index = destinations.firstIndex(of: input.primaryDestination) {
        let primary = destinations.remove(at: index)
        destinations.insert(primary, at: 0)
      }
      input.setDestinations(destinations)
    }
    dependencies.changed()
    var next = state
    next.acceptedRevisions[context.senderID] = context.revision
    try dependencies.saveState(next)
    state = next
    return true
  }
}

/// Atomic local revision storage; this record does not synchronize through an App Group.
public struct CompanionSyncStateStore: Sendable {
  private let url: URL

  /// Supplies the host-owned storage directory.
  public init(directory: URL) {
    url = directory.appendingPathComponent("companion-sync.json")
  }

  /// Returns nil only for an absent record; incompatible records remain intact and throw.
  public func load() throws -> CompanionSyncState? {
    do {
      return try JSONDecoder().decode(CompanionSyncState.self, from: Data(contentsOf: url))
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return nil
    }
  }

  /// Creates the directory and atomically commits revision metadata.
  public func save(_ state: CompanionSyncState) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(state).write(to: url, options: .atomic)
  }
}
