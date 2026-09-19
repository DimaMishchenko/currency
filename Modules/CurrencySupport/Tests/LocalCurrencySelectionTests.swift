import Foundation
import Testing

@testable import CurrencySupport

struct LocalCurrencySelectionTests {
  private func withStore(_ body: (CurrencyStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(CurrencyStore(directory: directory))
  }

  @Test func localIntentFollowsObservationsWithoutPersistingResolvedCurrency() throws {
    try withStore { store in
      try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      try store.saveWidgetLocationStatus(.available)
      try store.updateInput {
        $0.setDestinations(["USD"])
        $0.setUsesLocalCurrency(true)
      }
      #expect(store.input().destinations == ["USD", "CZK"])
      #expect(WidgetSelection.appConfiguration(store.input()) == ["EUR", "USD", "@local"])
      #expect(
        WidgetSelection.board(base: "EUR", targets: WidgetSelection.appConfiguration(store.input()))
          == ["EUR", "USD", "@local"])
      try store.saveWidgetLocation(WidgetLocation(country: "GB", currency: "GBP"))
      #expect(store.input().destinations == ["USD", "GBP"])
      #expect(store.input().manualDestinations == ["USD"])
      let data = try Data(contentsOf: store.directory.appendingPathComponent("input.json"))
      #expect(!String(decoding: data, as: UTF8.self).contains("CZK"))
      #expect(try JSONDecoder().decode(ConverterState.self, from: data).usesLocalCurrency)
    }
  }

  @Test func revokedPermissionHidesObservationButPreservesLocalIntent() throws {
    try withStore { store in
      try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      try store.updateInput {
        $0.setDestinations([]); $0.setUsesLocalCurrency(true)
      }
      try store.saveWidgetLocationStatus(.denied)
      #expect(store.input().usesLocalCurrency)
      #expect(store.input().localCurrencyCode == nil)
      #expect(store.input().destinations.isEmpty)
      #expect(
        WidgetSelection.calculator(
          app: store.input(), custom: nil, usesCustom: false, includeLocal: false) == [
            "EUR", "@local"
          ])
    }
  }

  @Test func localKeepsIndependentRowsAndDoesNotChangeExplicitSelections() {
    var input = ConverterState()
    input.setDestinations(["USD", "CZK"])
    input.setUsesLocalCurrency(true)
    input.resolveLocalCurrency(WidgetLocation(country: "CZ", currency: "CZK"), status: .available)
    #expect(input.destinations == ["USD", "CZK"])
    #expect(input.destinationRows.map(\.id) == ["USD", "CZK", "@local"])
    #expect(input.destinationRows.map(\.code) == ["USD", "CZK", "CZK"])
    input.changeSource("CZK")
    #expect(input.destinationRows.map(\.code) == ["USD", "EUR", "CZK"])
    #expect(input.destinations == ["USD", "EUR"])
    #expect(input.usesLocalCurrency)
    input.resolveLocalCurrency(WidgetLocation(country: "GB", currency: "GBP"), status: .available)
    #expect(input.destinations == ["USD", "EUR", "GBP"])
    input.removeDestination(WidgetSelection.localID)
    #expect(!input.usesLocalCurrency)
    #expect(input.destinations == ["USD", "EUR"])
  }

  @Test func fixedAndLocalSelectionsPersistAndRemoveIndependently() throws {
    try withStore { store in
      try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      try store.saveWidgetLocationStatus(.available)
      try store.updateInput {
        $0.setDestinations([])
        $0.setUsesLocalCurrency(true)
      }
      #expect(!store.input().manualDestinations.contains("CZK"))
      try store.updateInput { $0.setDestinations(["CZK"]) }
      #expect(store.input().destinationRows.map(\.id) == ["CZK", "@local"])
      #expect(store.input().destinationRows.map(\.code) == ["CZK", "CZK"])
      #expect(WidgetSelection.appConfiguration(store.input()) == ["EUR", "CZK", "@local"])
      try store.saveWidgetLocation(WidgetLocation(country: "GB", currency: "GBP"))
      #expect(store.input().destinationRows.map(\.code) == ["CZK", "GBP"])
      try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      try store.updateInput { $0.removeDestination("CZK") }
      #expect(store.input().destinationRows.map(\.id) == ["@local"])
      try store.updateInput { $0.setDestinations(["CZK"]) }
      try store.updateInput { $0.removeDestination(WidgetSelection.localID) }
      #expect(store.input().destinationRows.map(\.id) == ["CZK"])
      #expect(!store.input().usesLocalCurrency)
      try store.updateInput { $0.setUsesLocalCurrency(true) }
      try store.saveWidgetLocationStatus(.denied)
      #expect(store.input().destinationRows.map(\.id) == ["CZK"])
      #expect(store.input().usesLocalCurrency)
    }
  }

  @Test func automaticRefreshIsDailyAndFailureRetriesAreThrottledAcrossStores() throws {
    try withStore { store in
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      try store.saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK", updatedAt: now))
      try store.saveWidgetLocationStatus(.available)
      #expect(try !store.claimLocalCurrencyRefresh(now: now.addingTimeInterval(86399)))
      #expect(try store.claimLocalCurrencyRefresh(now: now.addingTimeInterval(86400)))
      let other = CurrencyStore(directory: store.directory)
      #expect(try !other.claimLocalCurrencyRefresh(now: now.addingTimeInterval(86401)))
      try store.saveWidgetLocationStatus(.failed)
      #expect(try !other.claimLocalCurrencyRefresh(now: now.addingTimeInterval(89999)))
      #expect(try other.claimLocalCurrencyRefresh(now: now.addingTimeInterval(90000)))
      try store.saveWidgetLocationStatus(.removed)
      #expect(try !other.claimLocalCurrencyRefresh(now: now.addingTimeInterval(180000)))
    }
  }

  @Test func staleAndFailedObservationsAreExplicitlyMarked() {
    var input = ConverterState()
    input.setUsesLocalCurrency(true)
    input.resolveLocalCurrency(
      WidgetLocation(country: "CZ", currency: "CZK", updatedAt: .distantPast), status: .available)
    #expect(input.localCurrencyIsStale)
    input.resolveLocalCurrency(WidgetLocation(country: "CZ", currency: "CZK"), status: .failed)
    #expect(input.localCurrencyIsStale)
    input.resolveLocalCurrency(WidgetLocation(country: "CZ", currency: "CZK"), status: .available)
    #expect(!input.localCurrencyIsStale)
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
}
