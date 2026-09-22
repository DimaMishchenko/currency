import AppIntents
import Conversion
import ExchangeRates
import Foundation
import Widgets

/// Retains the persisted History entity identity; presentation and choices use the shared picker.
struct HistoryCurrency: AppEntity {
  static let appBase = "@appBase"
  static let appFirst = "@appFirst"
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("currencyEntity", defaultValue: "Currency", table: "Widgets"))
  static let defaultQuery = HistoryCurrencyQuery()
  let id: String

  init(_ id: String) { self.id = id }

  var displayRepresentation: DisplayRepresentation {
    currencyRepresentation(id)
  }
}

struct HistoryCurrencyQuery: EntityStringQuery {
  private let defaultID: String
  private let readInput: @Sendable () -> ConverterState

  init() { self.init(defaultID: HistoryCurrency.appBase) }

  init(defaultID: String) {
    self.init(defaultID: defaultID, readInput: WidgetComposition.readInput())
  }

  init(defaultID: String, readInput: @escaping @Sendable () -> ConverterState) {
    self.defaultID = defaultID
    self.readInput = readInput
  }

  func defaultResult() async -> HistoryCurrency? { resolve(defaultID) }

  private func resolve(_ id: String) -> HistoryCurrency? {
    let input = readInput()
    let code: String?
    switch id {
    case HistoryCurrency.appBase: code = input.source
    case HistoryCurrency.appFirst: code = input.destinationRows.first?.code
    default: code = id
    }
    guard let code, CurrencyCatalog.codes.contains(code) || code == localCurrencyID
    else { return nil }
    return HistoryCurrency(code)
  }

  func entities(for identifiers: [String]) async throws -> [HistoryCurrency] {
    identifiers.compactMap(resolve)
  }

  func suggestedEntities() async throws -> IntentItemCollection<HistoryCurrency> {
    currencySections(input: readInput(), allowsLocal: true, make: HistoryCurrency.init)
  }

  func entities(matching string: String) async throws -> IntentItemCollection<HistoryCurrency> {
    let matches = try await ComparisonCurrencyQuery(readInput: readInput).entities(matching: string)
    return IntentItemCollection(items: matches.items.map { HistoryCurrency($0.id) })
  }
}

enum HistoryWidgetRange: String, AppEnum, CaseIterable {
  case week, month, quarter, year, all

  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("historyRange", defaultValue: "Range", table: "Widgets"))
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .week: DisplayRepresentation(
      title: LocalizedStringResource("historyWeek", defaultValue: "1 week", table: "Widgets")),
    .month: DisplayRepresentation(
      title: LocalizedStringResource("historyMonth", defaultValue: "1 month", table: "Widgets")),
    .quarter: DisplayRepresentation(
      title: LocalizedStringResource("historyQuarter", defaultValue: "3 months", table: "Widgets")),
    .year: DisplayRepresentation(
      title: LocalizedStringResource("historyYear", defaultValue: "1 year", table: "Widgets")),
    .all: DisplayRepresentation(
      title: LocalizedStringResource("historyAll", defaultValue: "All history", table: "Widgets"))
  ]

  var range: HistoryRange {
    switch self {
    case .week: .week
    case .month: .month
    case .quarter: .quarter
    case .year: .year
    case .all: .all
    }
  }
}

struct HistorySettings: WidgetConfigurationIntent {
  static let title = LocalizedStringResource(
    "historySettings", defaultValue: "History settings", table: "Widgets")

  @Parameter(
    title: LocalizedStringResource("baseParameter", defaultValue: "Base", table: "Widgets"),
    query: HistoryCurrencyQuery())
  var base: HistoryCurrency?

  @Parameter(
    title: LocalizedStringResource(
      "comparisonParameter", defaultValue: "Comparison", table: "Widgets"),
    query: HistoryCurrencyQuery(defaultID: HistoryCurrency.appFirst))
  var comparison: HistoryCurrency?

  @Parameter(
    title: LocalizedStringResource("historyRange", defaultValue: "Range", table: "Widgets"),
    default: .month)
  var range: HistoryWidgetRange

  static var parameterSummary: some ParameterSummary {
    Summary("Refreshes daily. Crypto history requires a USD comparison.", table: "Widgets") {
      \.$base; \.$comparison; \.$range
    }
  }

  func pair(input: ConverterState, localCurrency: String? = nil) -> HistoryWidgetPair {
    func resolve(_ choice: HistoryCurrency?) -> String? {
      guard let choice else { return nil }
      return switch choice.id {
      case localCurrencyID: localCurrency ?? localCurrencyID
      case HistoryCurrency.appBase: input.source
      case HistoryCurrency.appFirst: input.destinationRows.first?.code
      default: choice.id
      }
    }
    return HistoryWidgetPair(app: input, base: resolve(base), quote: resolve(comparison))
  }
}
