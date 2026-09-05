import CurrencySupport
import ExchangeRates
import WidgetKit

struct SuiteEntry: TimelineEntry {
  var date: Date
  var spec: WidgetSpec
  var input: WidgetInput
  var snapshot: RateSnapshot
}

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
      return Timeline(entries: [current], policy: .after(.now.addingTimeInterval(1800)))
    }
    _ = try? await CurrencyStore.shared.refreshRates(using: RateService())
    return Timeline(
      entries: [entry(configuration)],
      policy: .after(.now.addingTimeInterval(1800)))
  }

  private func entry(_ configuration: Configuration) -> SuiteEntry {
    let store = CurrencyStore.shared
    let spec = configuration.specification(kind: kind, location: store.widgetLocation())
    return SuiteEntry(
      date: .now, spec: spec,
      input: store.widgetInput(key: spec.key, codes: spec.codes, amount: spec.amount),
      snapshot: store.loadRates())
  }
}
