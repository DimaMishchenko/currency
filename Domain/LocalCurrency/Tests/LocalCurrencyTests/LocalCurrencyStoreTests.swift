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
}
