import CurrencySupport
import ExchangeRates
import OSLog
import WidgetKit
import WidgetPresentation

struct SuiteTimeline<Configuration: SuiteConfiguration>: AppIntentTimelineProvider {
  let kind: String

  func placeholder(in context: Context) -> SuiteEntry {
    entry(Configuration())
  }

  func snapshot(for configuration: Configuration, in context: Context) async -> SuiteEntry {
    entry(configuration)
  }

  func timeline(
    for configuration: Configuration,
    in context: Context
  ) async -> Timeline<SuiteEntry> {
    let current = entry(configuration)
    if Date().timeIntervalSince(current.input.editedAt ?? .distantPast) < 60 {
      // A tap never waits for network refresh or a second read of the same cached files.
      return timeline(starting: current)
    }
    let result = try? await CurrencyStore.shared.refreshRates(
      using: RateService(), force: current.snapshot.quotes.isEmpty, providerTimeout: .seconds(2))
    let refreshed = entry(configuration)
    return timeline(starting: refreshed, retry: result == nil || refreshed.snapshot.quotes.isEmpty)
  }

  private func timeline(starting current: SuiteEntry, retry: Bool = false) -> Timeline<SuiteEntry> {
    var entries = [current]
    if current.spec.usesLocation, current.spec.localCode != nil, !current.spec.localIsStale,
      let location = CurrencyStore.shared.widgetLocation()
    {
      var stale = current
      stale.date = location.updatedAt.addingTimeInterval(86400)
      stale.spec.localIsStale = true
      if stale.date > current.date { entries.append(stale) }
    }
    return Timeline(entries: entries, policy: .after(.now.addingTimeInterval(retry ? 300 : 1800)))
  }

  private func entry(_ configuration: Configuration) -> SuiteEntry {
    let store = CurrencyStore.shared
    let spec = configuration.specification(kind: kind, location: store.widgetLocation())
    #if DEBUG
      Logger(subsystem: "com.dimasike.currency", category: "WidgetConfiguration")
        .debug(
          "Timeline kind=\(kind, privacy: .public) instance=\(spec.instanceID ?? "nil", privacy: .public) key=\(spec.key, privacy: .public)"
        )
    #endif
    var input = store.widgetInput(key: spec.key, codes: spec.codes, amount: spec.amount)
    let rates = store.loadRates()
    if spec.synchronized { input.synchronize(with: store.input(), snapshot: rates) }
    return SuiteEntry(
      date: .now, spec: spec,
      input: input,
      snapshot: rates)
  }
}
