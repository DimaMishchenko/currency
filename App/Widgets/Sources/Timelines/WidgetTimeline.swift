import Conversion
import ExchangeRates
import Foundation
import LocalCurrency
import OSLog
import WidgetKit
import Widgets
import WidgetsUI

struct SuiteTimeline<Configuration: SuiteConfiguration>: AppIntentTimelineProvider {
  let kind: String
  let dependencies: WidgetTimelineDependencies

  func placeholder(in context: Context) -> SuiteEntry { entry(Configuration()) }

  func snapshot(for configuration: Configuration, in context: Context) async -> SuiteEntry {
    entry(configuration)
  }

  func timeline(
    for configuration: Configuration, in context: Context
  ) async -> Timeline<SuiteEntry> {
    await loadTimeline(configuration)
  }

  /// The actual provider path, also exercised without constructing a WidgetKit context.
  func loadTimeline(_ configuration: Configuration) async -> Timeline<SuiteEntry> {
    let current = entry(configuration)
    if dependencies.now().timeIntervalSince(current.input.editedAt ?? .distantPast) < 60 {
      // A tap never waits for network refresh or a second read of cached input.
      return timeline(starting: current)
    }
    if current.spec.usesLocation { await dependencies.refreshLocalCurrency() }
    let result = try? await dependencies.refreshRates(current.snapshot.quotes.isEmpty)
    let refreshed = entry(configuration)
    return timeline(starting: refreshed, retry: result == nil || refreshed.snapshot.quotes.isEmpty)
  }

  func timeline(starting current: SuiteEntry, retry: Bool = false) -> Timeline<SuiteEntry> {
    var entries = [current]
    if current.spec.usesLocation, current.spec.localCode != nil, !current.spec.localIsStale,
      let location = dependencies.location()
    {
      var stale = current
      stale.date = location.updatedAt.addingTimeInterval(86400)
      stale.spec.localIsStale = true
      if stale.date > current.date { entries.append(stale) }
    }
    return Timeline(
      entries: entries,
      policy: .after(dependencies.now().addingTimeInterval(retry ? 300 : 1800)))
  }

  func entry(_ configuration: Configuration) -> SuiteEntry {
    let app = dependencies.input()
    let spec = configuration.specification(
      kind: kind, input: app, location: dependencies.location(),
      status: dependencies.locationStatus())
    #if DEBUG
      Logger(subsystem: "com.dimasike.currency", category: "WidgetConfiguration")
        .debug(
          "Timeline kind=\(kind, privacy: .public) instance=\(spec.instanceID ?? "nil", privacy: .public) key=\(spec.key, privacy: .public)"
        )
    #endif
    var input = dependencies.widgetInput(spec.key, spec.codes, spec.amount)
    let rates = dependencies.rates()
    if spec.synchronized { input.synchronize(with: app, snapshot: rates) }
    return SuiteEntry(date: dependencies.now(), spec: spec, input: input, snapshot: rates)
  }
}
