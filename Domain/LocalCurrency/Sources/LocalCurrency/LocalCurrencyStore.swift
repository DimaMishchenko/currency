import Foundation

private struct LocalCurrencyRefreshRecord: Codable {
  var attemptedAt: Date?
  var generation: UUID?
}

/// Coordinated persistence for localcurrencystore records shared by app and widget processes.
public struct LocalCurrencyStore: Sendable {
  /// Explicit directory supplied by the executable or an isolated test.
  public let directory: URL
  /// Creates a store without discovering a global container.
  public init(directory: URL) { self.directory = directory }
  /// Claims a shared refresh opportunity so multiple app/widget processes do not duplicate work.
  public func claimLocalCurrencyRefresh(now: Date = .now) throws -> Bool {
    try coordinate("widget-location-refresh.json") {
      if widgetLocationStatus() == .removed { return false }
      if widgetLocationStatus() == .available, widgetLocation()?.isFresh(now: now) == true {
        return false
      }
      var record = localRefreshRecord()
      if let attempted = record.attemptedAt,
        now >= attempted, now.timeIntervalSince(attempted) < 3600
      {
        return false
      }
      record.attemptedAt = now
      try saveLocalRefreshRecord(record)
      return true
    }
  }
  private func localRefreshRecord() -> LocalCurrencyRefreshRecord {
    guard
      let data = try? Data(
        contentsOf: directory.appendingPathComponent("widget-location-refresh.json")),
      let record = try? JSONDecoder().decode(LocalCurrencyRefreshRecord.self, from: data)
    else { return LocalCurrencyRefreshRecord() }
    return record
  }

  private func saveLocalRefreshRecord(_ record: LocalCurrencyRefreshRecord) throws {
    try JSONEncoder().encode(record)
      .write(
        to: directory.appendingPathComponent("widget-location-refresh.json"), options: .atomic)
  }

  /// Begins a lookup generation that supersedes older callbacks across processes.
  public func beginLocalCurrencyLookup() throws -> UUID {
    try coordinate("widget-location-refresh.json") {
      var record = localRefreshRecord()
      let generation = UUID()
      record.generation = generation
      try saveLocalRefreshRecord(record)
      return generation
    }
  }

  /// Only the newest lookup may change the observation or mark it failed.
  public func completeLocalCurrencyLookup(
    _ generation: UUID, location: WidgetLocation?
  ) throws -> Bool {
    try coordinate("widget-location-refresh.json") {
      guard localRefreshRecord().generation == generation else { return false }
      if let location { try saveWidgetLocation(location) }
      try saveWidgetLocationStatus(location == nil ? .failed : .available)
      return true
    }
  }

  /// Invalidates pending generations before clearing the saved observation.
  public func clearLocalCurrency(outcome: WidgetLocationStatus) throws {
    try coordinate("widget-location-refresh.json") {
      var record = localRefreshRecord()
      record.generation = nil
      try saveLocalRefreshRecord(record)
      try saveWidgetLocationStatus(outcome)
      try saveWidgetLocation(nil)
    }
  }

  /// Loads the coarse location observation; freshness is evaluated by the consumer.
  public func widgetLocation() -> WidgetLocation? {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("widget-location.json"))
    else { return nil }
    return try? JSONDecoder().decode(WidgetLocation.self, from: data)
  }

  /// Atomically saves or removes the opt-in coarse location cache.
  public func saveWidgetLocation(_ location: WidgetLocation?) throws {
    try coordinate("widget-location.json") {
      let url = directory.appendingPathComponent("widget-location.json")
      if let location {
        try JSONEncoder().encode(location).write(to: url, options: .atomic)
      } else if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    }
  }
  /// Loads saved permission status, inferring legacy observation availability.
  public func widgetLocationStatus() -> WidgetLocationStatus {
    guard
      let data = try? Data(
        contentsOf: directory.appendingPathComponent("widget-location-status.json")),
      let status = try? JSONDecoder().decode(WidgetLocationStatus.self, from: data)
    else { return widgetLocation() == nil ? .notDetermined : .available }
    return status
  }

  /// Atomically persists the latest permission or lookup outcome.
  public func saveWidgetLocationStatus(_ status: WidgetLocationStatus) throws {
    try coordinate("widget-location-status.json") {
      try JSONEncoder().encode(status)
        .write(
          to: directory.appendingPathComponent("widget-location-status.json"), options: .atomic)
    }
  }
  func coordinate<Value>(_ filename: String, action: () throws -> Value) throws -> Value {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var coordinationError: NSError?
    var result: Result<Value, Error>?
    NSFileCoordinator()
      .coordinate(
        writingItemAt: directory.appendingPathComponent(filename), options: .forMerging,
        error: &coordinationError
      ) { _ in result = Result { try action() } }
    if let coordinationError { throw coordinationError }
    guard let result else { throw CocoaError(.fileWriteUnknown) }
    return try result.get()
  }
}
