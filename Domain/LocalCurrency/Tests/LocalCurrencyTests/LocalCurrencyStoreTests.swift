import Foundation
import Testing

@testable import LocalCurrency

struct LocalCurrencyStoreTests {
  private func withStore(_ body: (LocalCurrencyStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(LocalCurrencyStore(directory: directory))
  }
  @Test func automaticRefreshIsDailyAndFailureRetriesAreThrottledAcrossStores() throws {
    try withStore { store in
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK", updatedAt: now))
      try store.saveWidgetLocationStatus(.available)
      #expect(try !store.claimLocalCurrencyRefresh(now: now.addingTimeInterval(86399)))
      #expect(try store.claimLocalCurrencyRefresh(now: now.addingTimeInterval(86400)))
      let other = LocalCurrencyStore(directory: store.directory)
      #expect(try !other.claimLocalCurrencyRefresh(now: now.addingTimeInterval(86401)))
      try store.saveWidgetLocationStatus(.failed)
      #expect(try !other.claimLocalCurrencyRefresh(now: now.addingTimeInterval(89999)))
      #expect(try other.claimLocalCurrencyRefresh(now: now.addingTimeInterval(90000)))
      try store.saveWidgetLocationStatus(.removed)
      #expect(try !other.claimLocalCurrencyRefresh(now: now.addingTimeInterval(180000)))
    }
  }

  @Test func olderLookupCannotReplaceNewerSuccessOrRestoreRevokedObservation() throws {
    try withStore { store in
      let first = try store.beginLocalCurrencyLookup()
      let second = try store.beginLocalCurrencyLookup()
      let latest = WidgetLocation(country: "GB", currency: "GBP")
      #expect(try store.completeLocalCurrencyLookup(second, location: latest))
      #expect(try !store.completeLocalCurrencyLookup(first, location: nil))
      #expect(
        try !store.completeLocalCurrencyLookup(
          first, location: WidgetLocation(country: "CZ", currency: "CZK")))
      #expect(store.widgetLocation() == latest)
      #expect(store.widgetLocationStatus() == .available)
      try store.clearLocalCurrency(outcome: .denied)
      #expect(try !store.completeLocalCurrencyLookup(second, location: latest))
      #expect(store.widgetLocation() == nil)
      #expect(store.widgetLocationStatus() == .denied)
    }
  }
  @Test func localCurrencyRequiresFreshSupportedCountry() throws {
    let now = Date()
    #expect(WidgetLocation.currency(for: "CZ") == "CZK")
    #expect(WidgetLocation.currency(for: "US") == "USD")
    #expect(WidgetLocation.currency(for: "XX") == nil)
    #expect(WidgetLocation(country: "CZ", currency: "CZK", updatedAt: now).isFresh(now: now))
    #expect(
      !WidgetLocation(country: "CZ", currency: "CZK", updatedAt: now.addingTimeInterval(-86400))
        .isFresh(now: now))
    #expect(!WidgetLocation(country: "CZ", currency: "BTC", updatedAt: now).isFresh(now: now))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalCurrencyStore(directory: directory)
    let local = WidgetLocation(country: "CZ", currency: "CZK", updatedAt: now)
    try store.saveWidgetLocation(local)
    #expect(store.widgetLocation() == local)
    try store.saveWidgetLocation(nil)
    #expect(store.widgetLocation() == nil)
  }
  @Test(arguments: ["complete", "clear", "status"])
  func failedCommitPreservesWholeRecordAndPendingGeneration(operation: String) throws {
    try withStore { store in
      let original = WidgetLocation(country: "CZ", currency: "CZK")
      try store.saveWidgetLocation(original)
      let generation = try store.beginLocalCurrencyLookup()
      let url = store.directory.appendingPathComponent("widget-location-refresh.json")
      let bytes = try Data(contentsOf: url)
      let failing = LocalCurrencyStore(
        directory: store.directory,
        writeRecord: { _, _ in
          throw CocoaError(.fileWriteOutOfSpace)
        })
      #expect(throws: (any Error).self) {
        switch operation {
        case "complete":
          _ = try failing.completeLocalCurrencyLookup(
            generation,
            location: WidgetLocation(country: "GB", currency: "GBP"))
        case "clear": try failing.clearLocalCurrency(outcome: .denied)
        default: try failing.saveWidgetLocationStatus(.failed)
        }
      }
      #expect(try Data(contentsOf: url) == bytes)
      #expect(store.widgetLocation() == original)
      #expect(store.widgetLocationStatus() == .available)
      #expect(
        try store.completeLocalCurrencyLookup(
          generation,
          location: WidgetLocation(country: "GB", currency: "GBP")))
    }
  }

  @Test func statusOnlyUpdatePreservesPendingGeneration() throws {
    try withStore { store in
      let generation = try store.beginLocalCurrencyLookup()
      try store.saveWidgetLocationStatus(.notDetermined)
      #expect(
        try store.completeLocalCurrencyLookup(
          generation,
          location: WidgetLocation(country: "CZ", currency: "CZK")))
      #expect(try !store.completeLocalCurrencyLookup(generation, location: nil))
      #expect(store.widgetLocationStatus() == .available)
    }
  }

  @Test func legacyMigrationPreservesGenerationAndThrottleAndErasesSeparateRecords() throws {
    struct LegacyRefresh: Codable { let attemptedAt: Date; let generation: UUID }
    try withStore { store in
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let generation = UUID()
      let location = WidgetLocation(country: "CZ", currency: "CZK", updatedAt: .distantPast)
      try FileManager.default.createDirectory(
        at: store.directory, withIntermediateDirectories: true)
      let url = store.directory.appendingPathComponent("widget-location-refresh.json")
      let observationURL = store.directory.appendingPathComponent("widget-location.json")
      let statusURL = store.directory.appendingPathComponent("widget-location-status.json")
      try JSONEncoder().encode(LegacyRefresh(attemptedAt: now, generation: generation))
        .write(to: url)
      try JSONEncoder().encode(location).write(to: observationURL)
      try JSONEncoder().encode(WidgetLocationStatus.failed).write(to: statusURL)
      #expect(store.widgetLocation() == location)
      #expect(store.widgetLocationStatus() == .failed)
      #expect(try !store.claimLocalCurrencyRefresh(now: now.addingTimeInterval(3599)))
      #expect(!FileManager.default.fileExists(atPath: observationURL.path))
      #expect(!FileManager.default.fileExists(atPath: statusURL.path))
      #expect(try store.completeLocalCurrencyLookup(generation, location: location))
      let object = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: url))
          as? [String: Any])
      #expect(object["version"] as? Int == 1)
      #expect(
        Set(try #require(object["location"] as? [String: Any]).keys)
          == ["country", "currency", "updatedAt"])
      try store.clearLocalCurrency(outcome: .removed)
      #expect(store.widgetLocation() == nil)
      #expect(try !store.completeLocalCurrencyLookup(generation, location: location))
      // Even deletion of the migrated record cannot find an old observation to resurrect.
      try FileManager.default.removeItem(at: url)
      #expect(store.widgetLocation() == nil)
    }
  }

  @Test(arguments: [
    Data("invalid".utf8), Data("{\"version\":99,\"status\":\"available\"}".utf8),
    Data("{\"status\":\"available\",\"location\":null}".utf8)
  ])
  func corruptCanonicalRecordNeverFallsBackOrOverwrites(_ bytes: Data) throws {
    try withStore { store in
      try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      let url = store.directory.appendingPathComponent("widget-location-refresh.json")
      try bytes.write(to: url)
      try JSONEncoder().encode(WidgetLocation(country: "GB", currency: "GBP"))
        .write(
          to: store.directory.appendingPathComponent("widget-location.json"))
      #expect(store.widgetLocation() == nil)
      #expect(store.widgetLocationStatus() == .notDetermined)
      #expect(throws: (any Error).self) { try store.clearLocalCurrency(outcome: .removed) }
      #expect(try Data(contentsOf: url) == bytes)
    }
  }

  @Test func interruptedLegacyCleanupPreservesOldStateAndRetriesBeforeClear() throws {
    struct LegacyRefresh: Codable { let generation: UUID }
    try withStore { store in
      try FileManager.default.createDirectory(
        at: store.directory, withIntermediateDirectories: true)
      let generation = UUID()
      let location = WidgetLocation(country: "CZ", currency: "CZK")
      let observationURL = store.directory.appendingPathComponent("widget-location.json")
      try JSONEncoder().encode(location).write(to: observationURL)
      try JSONEncoder().encode(LegacyRefresh(generation: generation))
        .write(
          to: store.directory.appendingPathComponent("widget-location-refresh.json"))
      let failing = LocalCurrencyStore(
        directory: store.directory,
        writeRecord: { try $0.write(to: $1, options: .atomic) },
        removeLegacy: { _ in throw CocoaError(.fileWriteNoPermission) })
      #expect(throws: (any Error).self) { try failing.clearLocalCurrency(outcome: .denied) }
      #expect(store.widgetLocation() == location)
      #expect(store.widgetLocationStatus() == .available)
      #expect(FileManager.default.fileExists(atPath: observationURL.path))
      // Retry completes erasure and invalidates the old generation in one final commit.
      try store.clearLocalCurrency(outcome: .denied)
      #expect(!FileManager.default.fileExists(atPath: observationURL.path))
      #expect(store.widgetLocation() == nil)
      #expect(store.widgetLocationStatus() == .denied)
      #expect(try !store.completeLocalCurrencyLookup(generation, location: location))
    }
  }

}
