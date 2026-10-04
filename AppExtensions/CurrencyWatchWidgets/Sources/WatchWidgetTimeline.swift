import AppIntents
import Conversion
import ExchangeRates
import Foundation
import WidgetKit
import Widgets

enum WatchWidgetStyle: String, Sendable {
  case pocket, board, mental, cash, favorites
  var kind: String { "CurrencyWatch-" + rawValue }
}

struct WatchWidgetEntry: TimelineEntry {
  let date: Date
  let style: WatchWidgetStyle
  let source: String
  let targets: [String]
  let input: WidgetInput
  let key: String
  let initialAmount: String
  let snapshot: RateSnapshot
  var refreshFailed = false
  var warning: RefreshWarning?
  var configurationIsValid = true

  var quote: String? { targets.first }
  var activeSource: String { input.active }
  var activeQuote: String? { input.active == source ? quote : source }
  var codes: [String] { [source] + targets }

  var evaluation: ConversionEvaluation? {
    guard configurationIsValid else { return nil }
    let destinations = input.active == source ? targets : [source]
    guard
      let request = try? ConversionRequest(
        amount: input.amount, source: input.active,
        destinations: destinations.map { ConversionDestination(code: $0) })
    else { return nil }
    return try? ConversionEvaluation(
      request: request, snapshot: snapshot, now: date, refreshFailed: refreshFailed,
      warning: warning)
  }

  func value(to code: String) -> Decimal? {
    evaluation?.results.first { $0.destination.code == code }?.amount
      .flatMap(WidgetMath.parseAmount)
  }

  func url(quote: String? = nil, details: Bool = false) -> URL {
    WatchWidgetRoute.url(
      source: activeSource, quote: quote ?? activeQuote, amount: input.amount, details: details)
  }
}

enum WatchWidgetRoute {
  static func url(
    source: String? = nil, quote: String? = nil, amount: String? = nil,
    details: Bool = false
  ) -> URL {
    var components = URLComponents()
    components.scheme = "currency-watch"
    let hasPair =
      source.map(CurrencyCatalog.codes.contains) == true
      && quote.map(CurrencyCatalog.codes.contains) == true && source != quote
    components.host = hasPair && details ? "details" : "convert"
    components.queryItems =
      hasPair
      ? [
        source.map { URLQueryItem(name: "source", value: $0) },
        quote.map { URLQueryItem(name: "quote", value: $0) },
        !details ? amount.map { URLQueryItem(name: "amount", value: $0) } : nil
      ]
      .compactMap { $0 } : []
    if components.queryItems?.isEmpty == true { components.queryItems = nil }
    guard let url = components.url else { preconditionFailure("Invalid Currency Watch route.") }
    return url
  }
}

enum WatchWidgetComposition {
  static func directory() -> URL { WatchWidgetAppGroup.directory() }

  static func input() -> ConverterState { ConversionStore(directory: directory()).input() }

  static func entry(
    style: WatchWidgetStyle, source: String?, targets: [String]?, amount: String,
    now: Date = .now
  ) -> WatchWidgetEntry {
    let directory = directory()
    let app = ConversionStore(directory: directory).input()
    let base = source ?? (style == .cash && !WidgetPresets.allows(app.source) ? "EUR" : app.source)
    let quotes = WidgetSelection.normalize(targets ?? app.manualDestinations)
    let alternate = base == "USD" ? "EUR" : "USD"
    let candidates =
      targets == nil
      ? quotes.filter { $0 != base && (style != .cash || WidgetPresets.allows($0)) }
      : quotes
    let selected =
      style == .board || style == .favorites
      ? candidates.filter { $0 != base }
      : Array((candidates.isEmpty && targets == nil ? [alternate] : candidates).prefix(1))
    let initial =
      WidgetMath.parseAmount(amount).map { NSDecimalNumber(decimal: $0).stringValue } ?? "1"
    let key = ([style.kind, base] + selected + [initial])
      .joined(separator: "|")
    let input = WidgetStore(directory: directory)
      .widgetInput(
        key: key, codes: [base] + selected, amount: initial)
    return WatchWidgetEntry(
      date: now, style: style, source: base, targets: selected, input: input, key: key,
      initialAmount: initial, snapshot: RateStore(directory: directory).loadRates(),
      configurationIsValid: WidgetMath.parseAmount(amount) != nil
        && CurrencyCatalog.codes.contains(base)
        && (style != .cash
          || (WidgetPresets.allows(base) && selected.allSatisfy(WidgetPresets.allows)))
        && (style == .board || style == .favorites
          || (selected.first != nil && selected.first != base))
    )
  }

  static func refresh(_ entry: WatchWidgetEntry) async -> WatchWidgetEntry {
    guard Date().timeIntervalSince(entry.input.editedAt ?? .distantPast) >= 60 else { return entry }
    var refreshed = entry
    do {
      let result = try await RateStore(directory: directory())
        .refreshRates(
          using: RateService(), force: entry.snapshot.quotes.isEmpty, providerTimeout: .seconds(2))
      refreshed = WatchWidgetEntry(
        date: .now, style: entry.style, source: entry.source, targets: entry.targets,
        input: WidgetStore(directory: directory())
          .widgetInput(
            key: entry.key, codes: entry.codes, amount: entry.initialAmount),
        key: entry.key, initialAmount: entry.initialAmount, snapshot: result.snapshot,
        warning: result.warning, configurationIsValid: entry.configurationIsValid)
    } catch { refreshed.refreshFailed = true }
    return refreshed
  }
}

struct WatchPairTimeline: AppIntentTimelineProvider {
  let style: WatchWidgetStyle
  func recommendations() -> [AppIntentRecommendation<WatchPairSettings>] { [] }
  func placeholder(in context: Context) -> WatchWidgetEntry {
    WatchWidgetPreview.entry(style: style)
  }
  func snapshot(for configuration: WatchPairSettings, in context: Context) async -> WatchWidgetEntry
  {
    context.isPreview ? WatchWidgetPreview.entry(style: style) : entry(configuration)
  }
  func timeline(
    for configuration: WatchPairSettings, in context: Context
  ) async -> Timeline<WatchWidgetEntry> {
    let current = await WatchWidgetComposition.refresh(entry(configuration))
    return Timeline(entries: [current], policy: .after(current.date.addingTimeInterval(1800)))
  }
  private func entry(_ configuration: WatchPairSettings) -> WatchWidgetEntry {
    WatchWidgetComposition.entry(
      style: style, source: configuration.source?.id,
      targets: configuration.quote.map { [$0.id] }, amount: configuration.amount)
  }
}

struct WatchCashTimeline: AppIntentTimelineProvider {
  func recommendations() -> [AppIntentRecommendation<WatchCashSettings>] { [] }
  func placeholder(in context: Context) -> WatchWidgetEntry {
    WatchWidgetPreview.entry(style: .cash)
  }
  func snapshot(for configuration: WatchCashSettings, in context: Context) async -> WatchWidgetEntry
  {
    context.isPreview ? WatchWidgetPreview.entry(style: .cash) : entry(configuration)
  }
  func timeline(
    for configuration: WatchCashSettings, in context: Context
  ) async -> Timeline<WatchWidgetEntry> {
    let current = await WatchWidgetComposition.refresh(entry(configuration))
    return Timeline(entries: [current], policy: .after(current.date.addingTimeInterval(1800)))
  }
  private func entry(_ configuration: WatchCashSettings) -> WatchWidgetEntry {
    WatchWidgetComposition.entry(
      style: .cash, source: configuration.source?.id,
      targets: configuration.quote.map { [$0.id] }, amount: configuration.amount)
  }
}

struct WatchBoardTimeline: AppIntentTimelineProvider {
  let style: WatchWidgetStyle
  func recommendations() -> [AppIntentRecommendation<WatchBoardSettings>] { [] }
  func placeholder(in context: Context) -> WatchWidgetEntry {
    WatchWidgetPreview.entry(style: style)
  }
  func snapshot(
    for configuration: WatchBoardSettings, in context: Context
  ) async -> WatchWidgetEntry {
    context.isPreview ? WatchWidgetPreview.entry(style: style) : entry(configuration)
  }
  func timeline(
    for configuration: WatchBoardSettings, in context: Context
  ) async -> Timeline<WatchWidgetEntry> {
    let current = await WatchWidgetComposition.refresh(entry(configuration))
    return Timeline(entries: [current], policy: .after(current.date.addingTimeInterval(1800)))
  }
  private func entry(_ configuration: WatchBoardSettings) -> WatchWidgetEntry {
    WatchWidgetComposition.entry(
      style: style, source: configuration.source?.id, targets: configuration.targets?.map(\.id),
      amount: configuration.amount)
  }
}

struct WatchHistoryEntry: TimelineEntry {
  let date: Date
  let snapshot: HistoryWidgetSnapshot
}

struct WatchHistoryTimeline: AppIntentTimelineProvider {
  func recommendations() -> [AppIntentRecommendation<WatchHistorySettings>] { [] }
  func placeholder(in context: Context) -> WatchHistoryEntry { WatchWidgetPreview.history() }
  func snapshot(
    for configuration: WatchHistorySettings, in context: Context
  ) async -> WatchHistoryEntry {
    context.isPreview ? WatchWidgetPreview.history() : await entry(configuration)
  }
  func timeline(
    for configuration: WatchHistorySettings, in context: Context
  ) async -> Timeline<WatchHistoryEntry> {
    let current = await entry(configuration)
    return Timeline(
      entries: [current], policy: .after(current.snapshot.nextRefresh(after: current.date)))
  }
  private func entry(_ configuration: WatchHistorySettings) async -> WatchHistoryEntry {
    let now = Date()
    let pair = HistoryWidgetPair(
      app: WatchWidgetComposition.input(), base: configuration.source?.id,
      quote: configuration.quote?.id)
    let range = configuration.range.value
    let result: HistoryResult
    if let request = pair.historyRequest {
      result = await HistoryService(
        directory: WatchWidgetComposition.directory(), client: NetworkClient(timeout: 8)
      )
      .load(
        base: request.base, quote: request.quote, range: range, now: now,
        cacheLifetime: range == .day ? 3600 : 86400)
    } else {
      result = HistoryResult(series: nil, issue: .unsupportedPair)
    }
    return WatchHistoryEntry(
      date: now, snapshot: HistoryWidgetSnapshot(pair: pair, range: range, result: result))
  }
}

enum WatchWidgetPreview {
  static func entry(style: WatchWidgetStyle) -> WatchWidgetEntry {
    let now = Date()
    return WatchWidgetEntry(
      date: now, style: style, source: "EUR", targets: ["USD", "GBP", "CZK"],
      input: WidgetInput(codes: ["EUR", "USD", "GBP", "CZK"]), key: "preview", initialAmount: "1",
      snapshot: RateSnapshot(
        quotes: [
          "EUR": ExchangeRate(1, published: "2026-10-04", source: RateSource(provider: .ecb)),
          "USD": ExchangeRate(1.16, published: "2026-10-04", source: RateSource(provider: .ecb)),
          "GBP": ExchangeRate(0.87, published: "2026-10-04", source: RateSource(provider: .ecb)),
          "CZK": ExchangeRate(24.4, published: "2026-10-04", source: RateSource(provider: .ecb))
        ], fetchedAt: now))
  }
  static func history() -> WatchHistoryEntry {
    let now = Date()
    let pair = HistoryWidgetPair(app: ConverterState())
    return WatchHistoryEntry(
      date: now,
      snapshot: HistoryWidgetSnapshot(
        pair: pair, range: .month,
        result: HistoryResult(
          series: HistorySeries(
            points: (0..<12)
              .map {
                HistoryPoint(
                  date: now.addingTimeInterval(Double($0 - 12) * 86400),
                  value: 1.1 + Double($0) * 0.004 + ($0.isMultiple(of: 3) ? 0.007 : 0))
              }, source: RateSource(provider: .frankfurter, observation: .dailyReference),
            fetchedAt: now), issue: nil)))
  }
}
