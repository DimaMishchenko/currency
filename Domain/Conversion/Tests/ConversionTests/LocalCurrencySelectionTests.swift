import Foundation
import LocalCurrency
import Testing

@testable import Conversion

struct LocalCurrencySelectionTests {
  private func withStore(_ body: (ConversionStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(ConversionStore(directory: directory))
  }
  @Test func localIntentFollowsObservationsWithoutPersistingResolvedCurrency() throws {
    try withStore { store in
      try LocalCurrencyStore(directory: store.directory)
        .saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      try LocalCurrencyStore(directory: store.directory).saveWidgetLocationStatus(.available)
      try store.updateInput {
        $0.setDestinations(["USD"])
        $0.setUsesLocalCurrency(true)
      }
      #expect(store.input().destinations == ["USD", "CZK"])
      #expect(CurrencySelection.appConfiguration(store.input()) == ["EUR", "USD", "@local"])
      try LocalCurrencyStore(directory: store.directory)
        .saveWidgetLocation(WidgetLocation(country: "GB", currency: "GBP"))
      #expect(store.input().destinations == ["USD", "GBP"])
      #expect(store.input().manualDestinations == ["USD"])
      let data = try Data(contentsOf: store.directory.appendingPathComponent("input.json"))
      #expect(!String(decoding: data, as: UTF8.self).contains("CZK"))
      #expect(try JSONDecoder().decode(ConverterState.self, from: data).usesLocalCurrency)
    }
  }

  @Test func revokedPermissionHidesObservationButPreservesLocalIntent() throws {
    try withStore { store in
      try LocalCurrencyStore(directory: store.directory)
        .saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      try store.updateInput {
        $0.setDestinations([]); $0.setUsesLocalCurrency(true)
      }
      try LocalCurrencyStore(directory: store.directory).saveWidgetLocationStatus(.denied)
      #expect(store.input().usesLocalCurrency)
      #expect(store.input().localCurrencyCode == nil)
      #expect(store.input().destinations.isEmpty)
      #expect(
        CurrencySelection.appConfiguration(store.input()) == [
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
    input.removeDestination(CurrencySelection.localID)
    #expect(!input.usesLocalCurrency)
    #expect(input.destinations == ["USD", "EUR"])
  }

  @Test func fixedAndLocalSelectionsPersistAndRemoveIndependently() throws {
    try withStore { store in
      try LocalCurrencyStore(directory: store.directory)
        .saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      try LocalCurrencyStore(directory: store.directory).saveWidgetLocationStatus(.available)
      try store.updateInput {
        $0.setDestinations([])
        $0.setUsesLocalCurrency(true)
      }
      #expect(!store.input().manualDestinations.contains("CZK"))
      try store.updateInput { $0.setDestinations(["CZK"]) }
      #expect(store.input().destinationRows.map(\.id) == ["CZK", "@local"])
      #expect(store.input().destinationRows.map(\.code) == ["CZK", "CZK"])
      #expect(CurrencySelection.appConfiguration(store.input()) == ["EUR", "CZK", "@local"])
      try LocalCurrencyStore(directory: store.directory)
        .saveWidgetLocation(WidgetLocation(country: "GB", currency: "GBP"))
      #expect(store.input().destinationRows.map(\.code) == ["CZK", "GBP"])
      try LocalCurrencyStore(directory: store.directory)
        .saveWidgetLocation(WidgetLocation(country: "CZ", currency: "CZK"))
      try store.updateInput { $0.removeDestination("CZK") }
      #expect(store.input().destinationRows.map(\.id) == ["@local"])
      try store.updateInput { $0.setDestinations(["CZK"]) }
      try store.updateInput { $0.removeDestination(CurrencySelection.localID) }
      #expect(store.input().destinationRows.map(\.id) == ["CZK"])
      #expect(!store.input().usesLocalCurrency)
      try store.updateInput { $0.setUsesLocalCurrency(true) }
      try LocalCurrencyStore(directory: store.directory).saveWidgetLocationStatus(.denied)
      #expect(store.input().destinationRows.map(\.id) == ["CZK"])
      #expect(store.input().usesLocalCurrency)
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
}
