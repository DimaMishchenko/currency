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
  var rates: @Sendable () -> RateSnapshot = { RateSnapshot() }
  var refreshRates: @Sendable () async -> Void = {}
  var saveContext: @Sendable (RateSnapshot, HistoryWidgetPair, Date) -> URL? = { _, _, _ in nil }
  var localSnapshot: @Sendable () -> (LocalCurrency.WidgetLocation?, WidgetLocationStatus) = {
    (nil, .notDetermined)
  }
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
    let entry = await entry(configuration, persistContext: true)
    return Timeline(
      entries: [entry], policy: .after(entry.snapshot.nextRefresh(after: dependencies.now())))
  }

  func entry(
    _ configuration: HistorySettings, persistContext: Bool = false
  ) async -> HistoryWidgetEntry {
    let now = dependencies.now()
    let (location, status) = dependencies.localSnapshot()
    let local = ResolvedCurrencySelection(
      codes: [WidgetSelection.localID], location: location, status: status, now: now)
    let pair = configuration.pair(input: dependencies.input(), localCurrency: local.localCode)
    let range = configuration.effectiveRange(for: pair)
    let result: HistoryResult
    await dependencies.refreshRates()
    let rates = dependencies.rates()
    if let request = pair.historyRequest {
      result = await dependencies.load(request.base, request.quote, range, now)
        .includingLatestQuote(
          from: rates, base: request.base, quote: request.quote, now: dependencies.now())
    } else {
      result = HistoryResult(series: nil, issue: .unsupportedPair)
    }
    return HistoryWidgetEntry(
      date: now,
      snapshot: HistoryWidgetSnapshot(pair: pair, range: range, result: result),
      locationStatus: status,
      openURL: persistContext ? dependencies.saveContext(rates, pair, now) : nil)
  }
}
