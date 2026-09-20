import Conversion
import ExchangeRates
import Foundation
import Home
import LocalCurrency

/// Real isolated stores keep concurrent-read editing regressions at the production boundary.
struct HomeTestStore {
  let directory: URL
  var conversion: ConversionStore { ConversionStore(directory: directory) }
  var rates: RateStore { RateStore(directory: directory) }
  var location: LocalCurrencyStore { LocalCurrencyStore(directory: directory) }
  func input() -> ConverterState { conversion.input() }
  func saveWidgetLocation(_ value: WidgetLocation) throws { try location.saveWidgetLocation(value) }
  @discardableResult
  func updateInput(_ action: (inout ConverterState) throws -> Void) throws -> ConverterState {
    try conversion.updateInput(action)
  }
}

@MainActor
func makeHomeModel(store: HomeTestStore, service: RateService) -> HomeModel {
  HomeModel(
    dependencies: HomeDependencies(
      readInput: { store.input() },
      readRates: { store.rates.loadRates() },
      readRateIssue: { nil },
      readLocalCurrency: {
        (store.location.widgetLocation(), store.location.widgetLocationStatus())
      },
      editInput: { try store.updateInput($0) },
      refreshRates: { try await store.rates.refreshRates(using: service, force: $0) },
      changes: { AsyncStream { $0.finish() } }))
}
