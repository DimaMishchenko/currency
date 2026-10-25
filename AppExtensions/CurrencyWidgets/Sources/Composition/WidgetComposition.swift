import AudioToolbox
import Conversion
import CurrencyApplication
import ExchangeRates
import Foundation
import LocalCurrency
import WidgetKit
import Widgets

enum WidgetComposition {
  private static let shortTapticSoundID: SystemSoundID = 1519

  private static func directory() -> URL {
    guard
      let directory = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.dimasike.currency.shared")
    else {
      preconditionFailure("CurrencyWidgets requires its configured App Group entitlement.")
    }
    return directory
  }

  static func readInput() -> @Sendable () -> ConverterState {
    { ConversionStore(directory: directory()).input() }
  }

  static func readHistoryLocalCurrency() -> @Sendable () -> String? {
    {
      let local = LocalCurrencyStore(directory: directory())
      let (location, status) = local.snapshot()
      return ResolvedCurrencySelection(
        codes: [WidgetSelection.localID], location: location, status: status
      )
      .localCode
    }
  }

  static func timeline() -> WidgetTimelineDependencies {
    let directory = directory()
    let conversion = ConversionStore(directory: directory)
    let rates = RateStore(directory: directory)
    let local = LocalCurrencyStore(directory: directory)
    let widgets = WidgetStore(directory: directory)
    return WidgetTimelineDependencies(
      input: { conversion.input() }, rates: { rates.loadRates() },
      localSnapshot: local.snapshot,
      widgetInput: { key, codes, amount in
        widgets.widgetInput(key: key, codes: codes, amount: amount)
      },
      refreshRates: { force in
        try await rates.refreshRates(
          using: RateService(directory: directory), force: force,
          providerTimeout: .seconds(2))
      },
      refreshLocalCurrency: {
        let controller = await LocalCurrencyController(
          store: local, timeoutDuration: .seconds(5), reloadWidgets: {})
        await controller.refreshForWidget()
      },
      now: { .now },
      saveContext: { snapshot, now in
        try? WidgetQuoteContextStore(directory: directory).save(snapshot, now: now)
      }, refreshInterval: CurrencyRateConfiguration.widgetRefreshInterval)
  }

  static func history() -> HistoryTimelineDependencies {
    let directory = directory()
    let conversion = ConversionStore(directory: directory)
    let local = LocalCurrencyStore(directory: directory)
    let rates = RateStore(directory: directory)
    let history = HistoryService(
      directory: directory, client: NetworkClient(timeout: 10))
    return HistoryTimelineDependencies(
      input: { conversion.input() },
      load: { base, quote, range, now in
        await history.load(
          base: base, quote: quote, range: range, now: now,
          cacheLifetime: range == .day ? 3600 : 86_400)
      },
      now: { .now }, rates: rates.loadRates,
      refreshRates: {
        _ = try? await rates.refreshRates(
          using: RateService(directory: directory), force: false,
          providerTimeout: .seconds(2))
      },
      saveContext: { snapshot, pair, now in
        try? WidgetQuoteContextStore(directory: directory)
          .save(snapshot, base: pair.base, quote: pair.quote, now: now)
      },
      synchronizeQuote: { base, quote, point in
        if (try? WidgetStore(directory: directory)
          .claimHistoryQuoteRefresh(base: base, quote: quote, point: point)) == true
        {
          WidgetCenter.shared.reloadTimelines(ofKind: "CurrencyHistory")
        }
      }, localSnapshot: local.snapshot)
  }

  static func action() -> WidgetActionDependencies {
    action(directory: directory())
  }

  static func action(directory: URL) -> WidgetActionDependencies {
    let rates = RateStore(directory: directory)
    let widgets = WidgetStore(directory: directory)
    return WidgetActionDependencies(
      rates: { rates.loadRates() },
      apply: { command, key, snapshot in
        try widgets.apply(command, key: key, snapshot: snapshot ?? rates.loadRates()) {
          guard command.spec.kind == "CurrencyConverter" else { return }
          try? ConversionUsageStore(directory: directory)
            .recordWidgetConversion(key: key, now: .now)
        }
      },
      reloadSynchronizedWidgets: {
        for kind in ["CurrencyConverter", "CurrencyBoard"] {
          WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
      },
      hapticsEnabled: { widgets.widgetHapticsEnabled() },
      playHaptic: { AudioServicesPlaySystemSound(shortTapticSoundID) })
  }
}
