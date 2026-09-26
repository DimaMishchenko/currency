import AppIntents
import Conversion
import CoreLocation
import CurrencyApplication
import ExchangeRates
import Foundation
import LocalCurrency
import WidgetKit

/// Explicit executable wiring usable by App Intents without a foreground feature or scene.
struct SystemActionComposition: Sendable {
  let action: ConversionAction
  let readSelected: @Sendable () -> [String]
  let readLocal: @Sendable () -> (LocalCurrency.WidgetLocation?, WidgetLocationStatus)

  init(directory: URL, service: RateService = RateService()) {
    let conversion = ConversionStore(directory: directory)
    let local = LocalCurrencyStore(directory: directory)
    let rates = RateStore(directory: directory)
    // The saved outcome is authoritative, with a current denial overriding old cache permission.
    let readLocal: @Sendable () -> (LocalCurrency.WidgetLocation?, WidgetLocationStatus) = {
      let (observation, saved) = local.snapshot()
      switch CLLocationManager().authorizationStatus {
      case .denied: return (nil, .denied)
      case .restricted: return (nil, .restricted)
      case .notDetermined: return (nil, .notDetermined)
      default: return (observation, saved)
      }
    }
    self.readLocal = readLocal
    readSelected = { CurrencySelection.appConfiguration(conversion.input()) }
    action = ConversionAction(
      dependencies: .init(
        readInput: conversion.input, readLocal: readLocal, readRates: rates.loadRates,
        refresh: { now in
          let result = try await rates.refreshRates(
            using: service, now: now, providerTimeout: .seconds(3))
          try Task.checkCancellation()
          WidgetCenter.shared.reloadAllTimelines()
          return result
        }))
  }
}
