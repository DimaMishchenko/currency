import CryptoKit
import Foundation

private struct LocalCurrencyRefreshRecord: Codable {
  var attemptedAt: Date?
  var generation: UUID?
}

extension CurrencyStore {
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

  func beginLocalCurrencyLookup() throws -> UUID {
    try coordinate("widget-location-refresh.json") {
      var record = localRefreshRecord()
      let generation = UUID()
      record.generation = generation
      try saveLocalRefreshRecord(record)
      return generation
    }
  }

  /// Only the newest lookup may change the observation or mark it failed.
  func completeLocalCurrencyLookup(_ generation: UUID, location: WidgetLocation?) throws -> Bool {
    try coordinate("widget-location-refresh.json") {
      guard localRefreshRecord().generation == generation else { return false }
      if let location { try saveWidgetLocation(location) }
      try saveWidgetLocationStatus(location == nil ? .failed : .available)
      return true
    }
  }

  func clearLocalCurrency(outcome: WidgetLocationStatus) throws {
    try coordinate("widget-location-refresh.json") {
      var record = localRefreshRecord()
      record.generation = nil
      try saveLocalRefreshRecord(record)
      try saveWidgetLocationStatus(outcome)
      try saveWidgetLocation(nil)
    }
  }

  private func widgetFilename(_ key: String) -> String {
    "widget-" + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
      + ".json"
  }

  /// Loads a configuration-specific input, recovering safely from missing or incompatible data.
  public func widgetInput(
    key: String, codes: [String], amount: String = "1"
  ) -> WidgetInput {
    guard
      let data = try? Data(
        contentsOf: directory.appendingPathComponent(widgetFilename(key))),
      var input = try? JSONDecoder().decode(WidgetInput.self, from: data)
    else { return WidgetInput(codes: codes, amount: amount) }
    input.reconcile(codes: codes)
    return input
  }

  /// Coordinates a widget mutation against the latest persisted state across processes.
  @discardableResult
  public func updateWidgetInput(
    key: String, codes: [String], amount: String = "1",
    mutation: (inout WidgetInput) -> Void
  ) throws -> WidgetInput {
    let filename = widgetFilename(key)
    return try coordinate(filename) {
      var state = widgetInput(key: key, codes: codes, amount: amount)
      mutation(&state)
      try JSONEncoder().encode(state)
        .write(to: directory.appendingPathComponent(filename), options: .atomic)
      return state
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
}
