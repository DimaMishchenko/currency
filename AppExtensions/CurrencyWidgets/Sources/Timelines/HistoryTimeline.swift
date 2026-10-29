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
  var saveContext: @Sendable (RateSnapshot, HistoryWidgetPair, HistoryRange, Date) -> URL? = {
    _, _, _, _ in nil
  }
  var synchronizeQuote: @Sendable (String, String, HistoryPoint) -> Void = { _, _, _ in }
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
    let loaded: HistoryResult
    await dependencies.refreshRates()
    if let request = pair.historyRequest {
      loaded = await dependencies.load(request.base, request.quote, range, now)
    } else {
      loaded = HistoryResult(series: nil, issue: .unsupportedPair)
    }
    let rates = dependencies.rates()
    let renderedAt = dependencies.now()
    let result: HistoryResult
    if let request = pair.historyRequest {
      result = loaded.includingLatestQuote(
        from: rates, base: request.base, quote: request.quote, now: renderedAt)
    } else {
      result = loaded
    }
    let snapshot = HistoryWidgetSnapshot(pair: pair, range: range, result: result)
    if persistContext, snapshot.series != nil, let request = pair.historyRequest,
      let point = rates.historyQuote(base: request.base, quote: request.quote, now: renderedAt),
      result.series?.points.last == point
    {
      dependencies.synchronizeQuote(request.base, request.quote, point)
    }
    return HistoryWidgetEntry(
      date: renderedAt,
      snapshot: snapshot,
      locationStatus: status,
      openURL: persistContext ? dependencies.saveContext(rates, pair, range, renderedAt) : nil)
  }
}
