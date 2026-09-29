import AppIntents
import Conversion
import ExchangeRates
import Foundation
import Widgets

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

  func defaultResult() async -> HistoryCurrency? {
    resolve(defaultID)
  }

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

  @available(iOS 27.0, *)
  func displayRepresentations(
    for identifiers: [String]
  ) async throws -> [String: DisplayRepresentation] {
    var representations: [String: DisplayRepresentation] = [:]
    for identifier in identifiers {
      if let entity = resolve(identifier) {
        representations[identifier] = entity.displayRepresentation
      }
    }
    return representations
  }

  func suggestedEntities() async throws -> IntentItemCollection<HistoryCurrency> {
    currencySections(input: readInput(), allowsLocal: true, make: HistoryCurrency.init)
  }

  func entities(matching string: String) async throws -> IntentItemCollection<HistoryCurrency> {
    currencyMatches(string, allowsLocal: true, make: HistoryCurrency.init)
  }
}

enum HistoryWidgetRange: String, AppEnum, CaseIterable {
  case day, week, month, quarter, year, all

  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("historyRange", defaultValue: "Range", table: "Widgets"))
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .day: DisplayRepresentation(
      title: LocalizedStringResource("historyDay", defaultValue: "1D", table: "Widgets")),
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
    case .day: .day
    case .week: .week
    case .month: .month
    case .quarter: .quarter
    case .year: .year
    case .all: .all
    }
  }

  static func available(for pair: HistoryWidgetPair) -> [Self] {
    pair.supportsIntradayHistory ? allCases : allCases.filter { $0 != .day }
  }
}

struct HistoryRangeOptionsProvider: DynamicOptionsProvider {
  private let readInput: @Sendable () -> ConverterState
  private let readLocalCurrency: @Sendable () -> String?

  init() {
    self.init(
      readInput: WidgetComposition.readInput(),
      readLocalCurrency: WidgetComposition.readHistoryLocalCurrency())
  }

  init(
    readInput: @escaping @Sendable () -> ConverterState,
    readLocalCurrency: @escaping @Sendable () -> String? = { nil }
  ) {
    self.readInput = readInput
    self.readLocalCurrency = readLocalCurrency
    _settings = IntentParameterDependency(\.$base, \.$comparison)
  }

  @IntentParameterDependency<HistorySettings> var settings: IntentProjection<HistorySettings>?

  func results() async throws -> [HistoryWidgetRange] {
    HistoryWidgetRange.available(
      for: HistorySettings.resolvePair(
        input: readInput(), base: settings?.base, comparison: settings?.comparison,
        localCurrency: readLocalCurrency()))
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
    default: .month, optionsProvider: HistoryRangeOptionsProvider())
  var range: HistoryWidgetRange

  static var parameterSummary: some ParameterSummary {
    Summary("1D refreshes hourly where available; other ranges daily.", table: "Widgets") {
      \.$base; \.$comparison; \.$range
    }
  }

  func availableRanges(
    input: ConverterState, localCurrency: String? = nil
  )
    -> [HistoryWidgetRange]
  {
    HistoryWidgetRange.available(for: pair(input: input, localCurrency: localCurrency))
  }

  func effectiveRange(for pair: HistoryWidgetPair) -> HistoryRange {
    range == .day && !pair.supportsIntradayHistory ? .month : range.range
  }

  func pair(input: ConverterState, localCurrency: String? = nil) -> HistoryWidgetPair {
    Self.resolvePair(input: input, base: base, comparison: comparison, localCurrency: localCurrency)
  }

  static func resolvePair(
    input: ConverterState, base: HistoryCurrency?, comparison: HistoryCurrency?,
    localCurrency: String? = nil
  ) -> HistoryWidgetPair {
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
