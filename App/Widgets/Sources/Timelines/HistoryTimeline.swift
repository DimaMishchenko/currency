import Conversion
import ExchangeRates
import Foundation
import LocalCurrency
import WidgetKit
import Widgets
import WidgetsUI

struct HistoryTimelineDependencies: Sendable {
  let input: @Sendable () -> ConverterState
  let load: @Sendable (String, String, HistoryRange, Date) async -> HistoryResult
  let now: @Sendable () -> Date
  var location: @Sendable () -> LocalCurrency.WidgetLocation? = { nil }
  var locationStatus: @Sendable () -> WidgetLocationStatus = { .notDetermined }
}

struct HistoryTimeline: AppIntentTimelineProvider {
  let dependencies: HistoryTimelineDependencies

  func placeholder(in context: Context) -> HistoryWidgetEntry {
    .preview(date: dependencies.now())
  }

  func snapshot(for configuration: HistorySettings, in context: Context) async -> HistoryWidgetEntry
  {
    if context.isPreview { return .preview(date: dependencies.now()) }
    return await entry(configuration)
  }

  func timeline(
    for configuration: HistorySettings, in context: Context
  ) async -> Timeline<HistoryWidgetEntry> {
    await loadTimeline(configuration)
  }

  func loadTimeline(_ configuration: HistorySettings) async -> Timeline<HistoryWidgetEntry> {
    let entry = await entry(configuration)
    return Timeline(
      entries: [entry], policy: .after(entry.snapshot.nextRefresh(after: dependencies.now())))
  }

  func entry(_ configuration: HistorySettings) async -> HistoryWidgetEntry {
    let now = dependencies.now()
    let status = dependencies.locationStatus()
    let local = ResolvedCurrencySelection(
      codes: [WidgetSelection.localID], location: dependencies.location(), status: status, now: now)
    let pair = configuration.pair(input: dependencies.input(), localCurrency: local.localCode)
    let range = configuration.range.range
    let result: HistoryResult
    if pair.isSupported, let quote = pair.quote {
      result = await dependencies.load(pair.base, quote, range, now)
    } else {
      result = HistoryResult(series: nil, issue: .unsupportedPair)
    }
    return HistoryWidgetEntry(
      date: now, snapshot: HistoryWidgetSnapshot(pair: pair, range: range, result: result),
      locationStatus: status)
  }
}
