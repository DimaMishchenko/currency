import CoordinatedFiles
import Foundation

/// The existing refresh filename remains the cross-process lock and now holds the whole record.
private struct LocalCurrencyRecord: Codable {
  var version: Int?
  var attemptedAt: Date?
  var generation: UUID?
  var location: WidgetLocation?
  var status: WidgetLocationStatus?
}

/// Coordinates permission, coarse observation, and lookup generations as one atomic record.
public struct LocalCurrencyStore: Sendable {
  /// Explicit directory supplied by the executable or an isolated test.
  public let directory: URL
  private let writeRecord: @Sendable (Data, URL) throws -> Void
  private let removeLegacy: @Sendable (URL) throws -> Void
  /// Creates a store without discovering a global container.
  public init(directory: URL) {
    self.init(directory: directory, writeRecord: { try $0.write(to: $1, options: .atomic) })
  }
  /// Commit seam used to exercise a failed atomic write without changing filesystem permissions.
  init(
    directory: URL, writeRecord: @escaping @Sendable (Data, URL) throws -> Void,
    removeLegacy: @escaping @Sendable (URL) throws -> Void = {
      try FileManager.default.removeItem(at: $0)
    }
  ) {
    self.directory = directory
    self.writeRecord = writeRecord
    self.removeLegacy = removeLegacy
  }
  private var recordURL: URL { directory.appendingPathComponent("widget-location-refresh.json") }

  private func readRecord() throws -> LocalCurrencyRecord {
    let data = try FileCoordination.dataIfPresent(at: recordURL)
    var record =
      try data.map { try JSONDecoder().decode(LocalCurrencyRecord.self, from: $0) }
      ?? LocalCurrencyRecord()
    if let version = record.version {
      guard version == 1, record.status != nil else { throw CocoaError(.coderReadCorrupt) }
      return record
    }
    if let data {
      let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      guard fields?["location"] == nil, fields?["status"] == nil else {
        throw CocoaError(.coderReadCorrupt)
      }
    }
    // Only the original refresh format (no version) imports legacy observation/status files.
    if let data = try FileCoordination.dataIfPresent(
      at: directory.appendingPathComponent("widget-location.json"))
    {
      record.location = try JSONDecoder().decode(WidgetLocation.self, from: data)
    }
    if let data = try FileCoordination.dataIfPresent(
      at: directory.appendingPathComponent("widget-location-status.json"))
    {
      record.status = try JSONDecoder().decode(WidgetLocationStatus.self, from: data)
    } else {
      record.status = record.location == nil ? .notDetermined : .available
    }
    return record
  }

  private func save(_ record: LocalCurrencyRecord) throws {
    try writeRecord(JSONEncoder().encode(record), recordURL)
  }

  private func mutate<Value>(_ action: (inout LocalCurrencyRecord) throws -> Value) throws -> Value
  {
    try FileCoordination.write(at: recordURL) {
      var record = try readRecord()
      if record.version == nil {
        // Preserve the complete legacy state before erasing its separate files. If cleanup fails,
        // the requested transition has not happened and a later mutation retries the cleanup.
        record.version = 1
        try save(record)
      }
      for filename in ["widget-location.json", "widget-location-status.json"] {
        let url = directory.appendingPathComponent(filename)
        do { try removeLegacy(url) } catch let error as CocoaError {
          if error.code != .fileNoSuchFile { throw error }
        }
      }
      let value = try action(&record)
      try save(record)
      return value
    }
  }

  /// Claims a shared refresh opportunity, keeping hourly failure retries and daily success reuse.
  public func claimLocalCurrencyRefresh(now: Date = .now) throws -> Bool {
    try mutate { record in
      if record.status == .removed { return false }
      if record.status == .available, record.location?.isFresh(now: now) == true { return false }
      if let attempted = record.attemptedAt,
        now >= attempted, now.timeIntervalSince(attempted) < 3600
      {
        return false
      }
      record.attemptedAt = now
      return true
    }
  }

  /// Begins a lookup generation that supersedes older callbacks across processes.
  public func beginLocalCurrencyLookup() throws -> UUID {
    try mutate { record in
      let generation = UUID()
      record.generation = generation
      return generation
    }
  }

  /// Commits observation and outcome together; only the newest pending lookup may complete.
  public func completeLocalCurrencyLookup(
    _ generation: UUID, location: WidgetLocation?
  ) throws -> Bool {
    try mutate { record in
      guard record.generation == generation else { return false }
      if let location { record.location = location }
      record.status = location == nil ? .failed : .available
      record.generation = nil
      return true
    }
  }

  /// Erases the coarse observation and invalidates callbacks in the same atomic commit.
  public func clearLocalCurrency(outcome: WidgetLocationStatus) throws {
    try mutate { record in
      record.generation = nil
      record.attemptedAt = nil
      record.status = outcome
      record.location = nil
    }
  }

  /// Loads only the coarse observation; corrupt records are never replaced during rendering.
  public func widgetLocation() -> WidgetLocation? { try? readRecord().location }

  /// Saves a coarse observation without superseding an active lookup generation.
  public func saveWidgetLocation(_ location: WidgetLocation?) throws {
    try mutate { record in
      record.location = location
      if record.status == .notDetermined, location != nil { record.status = .available }
      if record.status == .available, location == nil { record.status = .notDetermined }
    }
  }

  /// Loads saved authorization or lookup outcome, inferring availability only for legacy records.
  public func widgetLocationStatus() -> WidgetLocationStatus {
    (try? readRecord().status) ?? .notDetermined
  }

  /// Reads observation and authorization from the same coordinated record.
  public func snapshot() -> (WidgetLocation?, WidgetLocationStatus) {
    guard let record = try? readRecord() else { return (nil, .notDetermined) }
    return (record.location, record.status ?? .notDetermined)
  }

  /// Changes status while preserving the observation and any active lookup generation.
  public func saveWidgetLocationStatus(_ status: WidgetLocationStatus) throws {
    try mutate { $0.status = status }
  }
}
