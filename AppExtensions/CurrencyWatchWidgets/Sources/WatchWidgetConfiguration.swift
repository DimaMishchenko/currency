import AppIntents
import Conversion
import ExchangeRates
import Foundation
import Widgets

enum WatchWidgetStyle: String, Sendable {
  case pocket, board, mental, cash, favorites
  var kind: String { "CurrencyWatch-" + rawValue }
}

struct WatchCurrency: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("currency", defaultValue: "Currency", table: "WatchWidgets"))
  static let defaultQuery = WatchCurrencyQuery()
  let id: String

  init(_ id: String) { self.id = id }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(id)",
      subtitle:
        "\(CurrencyCatalog.assetName(id) ?? Locale.current.localizedString(forCurrencyCode: id) ?? id)"
    )
  }
}

func watchCurrencySections<Entity: AppEntity>(
  cashOnly: Bool = false, make: (String) -> Entity
) -> IntentItemCollection<Entity> {
  let input = WatchWidgetAppGroup.input()
  let allowed = CurrencyCatalog.codes.filter { !cashOnly || WidgetPresets.allows($0) }
  let preferred = WidgetSelection.normalize([input.source] + input.manualDestinations)
    .filter(allowed.contains)
  let remaining = allowed.filter { !preferred.contains($0) }.sorted()
  var sections: [IntentItemSection<Entity>] = []
  func append(_ title: LocalizedStringResource, _ codes: [String]) {
    if !codes.isEmpty { sections.append(IntentItemSection(title, items: codes.map(make))) }
  }
  append(
    LocalizedStringResource("favorites", defaultValue: "Watch favorites", table: "WatchWidgets"),
    preferred)
  append(
    LocalizedStringResource("currencies", defaultValue: "Currencies", table: "WatchWidgets"),
    remaining.filter { !CurrencyCatalog.crypto.contains($0) && !WidgetPresets.metals.contains($0) })
  append(
    LocalizedStringResource("metals", defaultValue: "Metals", table: "WatchWidgets"),
    remaining.filter(WidgetPresets.metals.contains))
  append(
    LocalizedStringResource("crypto", defaultValue: "Crypto", table: "WatchWidgets"),
    remaining.filter(CurrencyCatalog.crypto.contains))
  return IntentItemCollection(sections: sections)
}

func watchCurrencyMatches<Entity: AppEntity>(
  _ string: String, cashOnly: Bool = false, make: (String) -> Entity
) -> IntentItemCollection<Entity> {
  IntentItemCollection(
    items:
      CurrencyCatalog.search(string) {
        CurrencyCatalog.assetName($0) ?? Locale.current.localizedString(forCurrencyCode: $0) ?? $0
      }
      .filter { !cashOnly || WidgetPresets.allows($0) }
      .map(make))
}

struct WatchCurrencyQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [WatchCurrency] {
    identifiers.filter(CurrencyCatalog.codes.contains).map(WatchCurrency.init)
  }

  func suggestedEntities() async throws -> IntentItemCollection<WatchCurrency> {
    watchCurrencySections(make: WatchCurrency.init)
  }

  func entities(matching string: String) async throws -> IntentItemCollection<WatchCurrency> {
    watchCurrencyMatches(string, make: WatchCurrency.init)
  }
}

struct WatchCashCurrency: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource(
      "cashCurrency", defaultValue: "Currency or metal", table: "WatchWidgets"))
  static let defaultQuery = WatchCashQuery()
  let id: String

  init(_ id: String) { self.id = id }

  var displayRepresentation: DisplayRepresentation {
    WatchCurrency(id).displayRepresentation
  }
}

struct WatchCashQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [WatchCashCurrency] {
    identifiers.filter(WidgetPresets.allows).map(WatchCashCurrency.init)
  }

  func suggestedEntities() async throws -> IntentItemCollection<WatchCashCurrency> {
    watchCurrencySections(cashOnly: true, make: WatchCashCurrency.init)
  }

  func entities(matching string: String) async throws -> IntentItemCollection<WatchCashCurrency> {
    watchCurrencyMatches(string, cashOnly: true, make: WatchCashCurrency.init)
  }
}

struct WatchCashSettings: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "cashTitle", defaultValue: "Know Your Cash", table: "WatchWidgets")
  @Parameter(
    title: LocalizedStringResource(
      "source", defaultValue: "Source (empty follows Watch)", table: "WatchWidgets"))
  var source: WatchCashCurrency?
  @Parameter(
    title: LocalizedStringResource(
      "quote", defaultValue: "Comparison (empty follows Watch)", table: "WatchWidgets"))
  var quote: WatchCashCurrency?

  static var parameterSummary: some ParameterSummary {
    Summary {
      \.$source; \.$quote
    }
  }
}

struct WatchPairSettings: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "pairSettings", defaultValue: "Currency pair", table: "WatchWidgets")
  @Parameter(
    title: LocalizedStringResource(
      "source", defaultValue: "Source (empty follows Watch)", table: "WatchWidgets")) var source:
    WatchCurrency?
  @Parameter(
    title: LocalizedStringResource(
      "quote", defaultValue: "Comparison (empty follows Watch)", table: "WatchWidgets")) var quote:
    WatchCurrency?

  static var parameterSummary: some ParameterSummary {
    Summary {
      \.$source; \.$quote
    }
  }
}

struct WatchBoardSettings: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "boardSettings", defaultValue: "Currency board", table: "WatchWidgets")
  @Parameter(
    title: LocalizedStringResource(
      "source", defaultValue: "Source (empty follows Watch)", table: "WatchWidgets")) var source:
    WatchCurrency?
  @Parameter(
    title: LocalizedStringResource(
      "targets", defaultValue: "Currencies (empty follows Watch)", table: "WatchWidgets"))
  var targets: [WatchCurrency]?
  @Parameter(
    title: LocalizedStringResource("amount", defaultValue: "Amount", table: "WatchWidgets"),
    default: "1") var amount: String
  static var parameterSummary: some ParameterSummary {
    Summary {
      \.$source; \.$targets; \.$amount
    }
  }
}

enum WatchHistoryRange: String, AppEnum, CaseIterable {
  case day, week, month, quarter, year, all
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("range", defaultValue: "Range", table: "WatchWidgets"))
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .day: .init(
      title: LocalizedStringResource("day", defaultValue: "One day", table: "WatchWidgets")),
    .week: .init(
      title: LocalizedStringResource("week", defaultValue: "1 week", table: "WatchWidgets")),
    .month: .init(
      title: LocalizedStringResource("month", defaultValue: "1 month", table: "WatchWidgets")),
    .quarter: .init(
      title: LocalizedStringResource("quarter", defaultValue: "3 months", table: "WatchWidgets")),
    .year: .init(
      title: LocalizedStringResource("year", defaultValue: "1 year", table: "WatchWidgets")),
    .all: .init(
      title: LocalizedStringResource("all", defaultValue: "All history", table: "WatchWidgets"))
  ]
  var value: HistoryRange {
    switch self {
    case .day: .day
    case .week: .week
    case .month: .month
    case .quarter: .quarter
    case .year: .year
    case .all: .all
    }
  }
}

struct WatchHistoryRangeOptions: DynamicOptionsProvider {
  @IntentParameterDependency<WatchHistorySettings>(\.$source, \.$quote)
  var settings: IntentProjection<WatchHistorySettings>?

  func results() async throws -> [WatchHistoryRange] {
    let pair = HistoryWidgetPair(
      app: WatchWidgetAppGroup.input(), base: settings?.source.id, quote: settings?.quote.id)
    return pair.supportsIntradayHistory
      ? WatchHistoryRange.allCases
      : WatchHistoryRange.allCases.filter { $0 != .day }
  }
}

struct WatchHistorySettings: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "historySettings", defaultValue: "History settings", table: "WatchWidgets")
  @Parameter(
    title: LocalizedStringResource(
      "source", defaultValue: "Source (empty follows Watch)", table: "WatchWidgets")) var source:
    WatchCurrency?
  @Parameter(
    title: LocalizedStringResource(
      "quote", defaultValue: "Comparison (empty follows Watch)", table: "WatchWidgets")) var quote:
    WatchCurrency?
  @Parameter(
    title: LocalizedStringResource("range", defaultValue: "Range", table: "WatchWidgets"),
    default: .month, optionsProvider: WatchHistoryRangeOptions())
  var range: WatchHistoryRange
  static var parameterSummary: some ParameterSummary {
    Summary {
      \.$source; \.$quote; \.$range
    }
  }
}
