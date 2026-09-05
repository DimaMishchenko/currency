import AppIntents
import CurrencySupport
import ExchangeRates
import Foundation

private let localCurrencyID = "@local"

private func currencyRepresentation(_ code: String) -> DisplayRepresentation {
  if code == localCurrencyID {
    return DisplayRepresentation(
      title: LocalizedStringResource(
        "localCurrencyChoice", defaultValue: "Local currency", table: "Widgets"),
      subtitle: LocalizedStringResource(
        "localCurrencyChoiceHelp", defaultValue: "Set your location in the app", table: "Widgets"),
      image: .init(systemName: "location.fill"))
  }
  if let data = CurrencyIcon.pickerImageData(code) {
    return DisplayRepresentation(
      title: "\(code)", subtitle: "\(CurrencyDisplay.name(code))",
      image: .init(data: data, isTemplate: false))
  }
  return DisplayRepresentation(
    title: "\(CurrencyDisplay.flag(code)) \(code)", subtitle: "\(CurrencyDisplay.name(code))")
}

struct WidgetCurrency: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource(
      "currencyEntity", defaultValue: "Currency", table: "Widgets"))
  static let defaultQuery = CurrencyQuery()
  let id: String
  var displayRepresentation: DisplayRepresentation {
    currencyRepresentation(id)
  }

  init(_ code: String) { id = code }
}

struct CurrencyQuery: EntityStringQuery {
  func defaultResult() async -> WidgetCurrency? {
    WidgetCurrency("EUR")
  }
  func entities(for identifiers: [String]) async throws -> [WidgetCurrency] {
    identifiers.filter { CurrencyCatalog.codes.contains($0) }.map(WidgetCurrency.init)
  }

  func suggestedEntities() async throws -> [WidgetCurrency] {
    CurrencyCatalog.codes.map(WidgetCurrency.init)
  }

  func entities(matching string: String) async throws -> [WidgetCurrency] {
    CurrencyCatalog.codes
      .filter {
        $0.localizedCaseInsensitiveContains(string)
          || CurrencyDisplay.name($0).localizedCaseInsensitiveContains(string)
      }
      .map(WidgetCurrency.init)
  }
}

struct CashCurrency: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("cashEntity", defaultValue: "Currency or metal", table: "Widgets")
  )
  static let defaultQuery = CashQuery()
  let id: String
  var displayRepresentation: DisplayRepresentation {
    currencyRepresentation(id)
  }

  init(_ code: String) { id = code }
}

struct CashQuery: EntityStringQuery {
  func defaultResult() async -> CashCurrency? {
    CashCurrency("CZK")
  }
  func entities(for identifiers: [String]) async throws -> [CashCurrency] {
    identifiers.filter(WidgetPresets.allows).map(CashCurrency.init)
  }

  func suggestedEntities() async throws -> [CashCurrency] {
    CurrencyCatalog.codes.filter(WidgetPresets.allows).map(CashCurrency.init)
  }

  func entities(matching string: String) async throws -> [CashCurrency] {
    CurrencyCatalog.codes
      .filter {
        WidgetPresets.allows($0)
          && ($0.localizedCaseInsensitiveContains(string)
            || CurrencyDisplay.name($0).localizedCaseInsensitiveContains(string))
      }
      .map(CashCurrency.init)
  }
}

struct BaseCurrencyQuery: EntityStringQuery {
  func defaultResult() async -> WidgetCurrency? {
    WidgetCurrency("EUR")
  }
  func entities(for identifiers: [String]) async throws -> [WidgetCurrency] {
    try await CurrencyQuery().entities(for: identifiers)
  }
  func suggestedEntities() async throws -> [WidgetCurrency] {
    try await CurrencyQuery().suggestedEntities()
  }
  func entities(matching string: String) async throws -> [WidgetCurrency] {
    try await CurrencyQuery().entities(matching: string)
  }
}

struct CashBaseQuery: EntityStringQuery {
  func defaultResult() async -> CashCurrency? { CashCurrency("CZK") }
  func entities(for identifiers: [String]) async throws -> [CashCurrency] {
    try await CashQuery().entities(for: identifiers)
  }
  func suggestedEntities() async throws -> [CashCurrency] {
    try await CashQuery().suggestedEntities()
  }
  func entities(matching string: String) async throws -> [CashCurrency] {
    try await CashQuery().entities(matching: string)
  }
}

struct ComparisonCurrencyQuery: EntityStringQuery {
  func defaultResult() async -> WidgetCurrency? {
    WidgetCurrency("USD")
  }

  func entities(for identifiers: [String]) async throws -> [WidgetCurrency] {
    identifiers.filter { $0 == localCurrencyID || CurrencyCatalog.codes.contains($0) }
      .map(WidgetCurrency.init)
  }
  func suggestedEntities() async throws -> [WidgetCurrency] {
    [WidgetCurrency(localCurrencyID)] + (try await CurrencyQuery().suggestedEntities())
  }
  func entities(matching string: String) async throws -> [WidgetCurrency] {
    let localName = String(
      localized: "localCurrencyChoice", defaultValue: "Local currency", table: "Widgets")
    let local =
      localName.localizedCaseInsensitiveContains(string) ? [WidgetCurrency(localCurrencyID)] : []
    return local + (try await CurrencyQuery().entities(matching: string))
  }
}

struct CashComparisonQuery: EntityStringQuery {
  func defaultResult() async -> CashCurrency? { CashCurrency("EUR") }

  func entities(for identifiers: [String]) async throws -> [CashCurrency] {
    identifiers.filter { $0 == localCurrencyID || WidgetPresets.allows($0) }.map(CashCurrency.init)
  }
  func suggestedEntities() async throws -> [CashCurrency] {
    [CashCurrency(localCurrencyID)] + (try await CashQuery().suggestedEntities())
  }
  func entities(matching string: String) async throws -> [CashCurrency] {
    let localName = String(
      localized: "localCurrencyChoice", defaultValue: "Local currency", table: "Widgets")
    let local =
      localName.localizedCaseInsensitiveContains(string) ? [CashCurrency(localCurrencyID)] : []
    return local + (try await CashQuery().entities(matching: string))
  }
}

/// WidgetKit asks queries for defaults when presenting its native editor.
struct MultiCurrencyQuery: EntityStringQuery {
  func defaultResult() async -> [WidgetCurrency]? {
    ["EUR", "USD", "GBP", "CZK", "CHF", "JPY"].map(WidgetCurrency.init)
  }
  func entities(for identifiers: [String]) async throws -> [WidgetCurrency] {
    try await CurrencyQuery().entities(for: identifiers)
  }
  func suggestedEntities() async throws -> [WidgetCurrency] {
    try await CurrencyQuery().suggestedEntities()
  }
  func entities(matching string: String) async throws -> [WidgetCurrency] {
    try await CurrencyQuery().entities(matching: string)
  }
}

struct BoardCurrencyQuery: EntityStringQuery {
  func defaultResult() async -> [WidgetCurrency]? {
    ["USD", "GBP", "CZK", "CHF", "JPY", "BTC"].map(WidgetCurrency.init)
  }
  func entities(for identifiers: [String]) async throws -> [WidgetCurrency] {
    try await CurrencyQuery().entities(for: identifiers)
  }
  func suggestedEntities() async throws -> [WidgetCurrency] {
    try await CurrencyQuery().suggestedEntities()
  }
  func entities(matching string: String) async throws -> [WidgetCurrency] {
    try await CurrencyQuery().entities(matching: string)
  }
}

enum BoardCurrencyList: String, AppEnum {
  case selected, standard
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource(
      "listModeParameter", defaultValue: "Currency list", table: "Widgets"))
  static let caseDisplayRepresentations: [BoardCurrencyList: DisplayRepresentation] = [
    .selected: DisplayRepresentation(
      title: LocalizedStringResource(
        "selectedList", defaultValue: "Selected currencies", table: "Widgets")),
    .standard: DisplayRepresentation(
      title: LocalizedStringResource(
        "standardList", defaultValue: "Default currencies", table: "Widgets"))
  ]
}

/// A persisted configuration value, generated by WidgetKit when a widget is added.
/// Never generate this ID in a timeline or view: that would reset the saved input on refresh.
struct CalculatorInstance: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Calculator"
  static let defaultQuery = CalculatorInstanceQuery()
  let id: String
  var displayRepresentation: DisplayRepresentation { "Calculator" }
}

struct CalculatorInstanceQuery: EntityQuery {
  func defaultResult() async -> CalculatorInstance? {
    CalculatorInstance(id: UUID().uuidString)
  }
  func entities(for identifiers: [String]) async throws -> [CalculatorInstance] {
    identifiers.filter { UUID(uuidString: $0) != nil }.map { CalculatorInstance(id: $0) }
  }
  func suggestedEntities() async throws -> [CalculatorInstance] { [] }
}

protocol SuiteConfiguration: WidgetConfigurationIntent {
  func specification(kind: String, location: WidgetLocation?) -> WidgetSpec
}

struct WidgetSpec: Sendable {
  var kind: String
  var codes: [String]
  var amount = "1"
  var usesLocation = false
  var locationAvailable = false
  var instanceID: String?
  var key: String {
    if let instanceID { return "\(kind)|instance|\(instanceID)" }
    return ([kind] + codes).joined(separator: "|")
  }

  init(
    kind: String, codes: [String], amount: String = "1",
    local: Bool = false, location: WidgetLocation? = nil, instanceID: String? = nil
  ) {
    self.kind = kind
    var seen = Set<String>()
    let valid = codes.filter { CurrencyCatalog.codes.contains($0) }
    if kind == "CurrencyBoard", let base = valid.first {
      // Base and comparisons have distinct roles: selecting the base as a target is valid.
      self.codes = [base] + valid.dropFirst().filter { seen.insert($0).inserted }
    } else if kind == "CurrencyConverter" {
      self.codes = valid.filter { seen.insert($0).inserted }
    } else {
      self.codes = valid
    }
    if self.codes.isEmpty { self.codes = ["EUR", "USD"] }
    if local, let location, location.isFresh() {
      if self.codes.count > 1 {
        self.codes[1] = location.currency
      } else {
        self.codes.append(location.currency)
      }
      locationAvailable = true
    }
    self.instanceID = instanceID
    self.amount = amount
    usesLocation = local
  }
}

struct MultiSettings: SuiteConfiguration {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "multiSettings", defaultValue: "Multi-currency settings", table: "Widgets")
  @Parameter(
    title: LocalizedStringResource(
      "currenciesParameter", defaultValue: "Currencies", table: "Widgets"),
    default: ["EUR", "USD", "GBP", "CZK", "CHF", "JPY"].map(WidgetCurrency.init),
    size: .init(min: 2, max: 8), query: MultiCurrencyQuery()) var currencies: [WidgetCurrency]?
  @Parameter(title: "Calculator", query: CalculatorInstanceQuery())
  var instance: CalculatorInstance?

  static var parameterSummary: some ParameterSummary {
    Summary {
      \.$currencies
    }
  }

  func specification(kind: String, location: WidgetLocation?) -> WidgetSpec {
    WidgetSpec(
      kind: kind,
      codes: (currencies ?? ["EUR", "USD", "GBP", "CZK", "CHF", "JPY"].map(WidgetCurrency.init))
        .map(\.id),
      instanceID: instance?.id)
  }
}

struct PairSettings: SuiteConfiguration {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "pairSettings", defaultValue: "Currency pair", table: "Widgets")
  @Parameter(
    title: LocalizedStringResource("baseParameter", defaultValue: "Base", table: "Widgets"),
    default: WidgetCurrency("EUR"), query: BaseCurrencyQuery())
  var base: WidgetCurrency
  @Parameter(
    title: LocalizedStringResource(
      "comparisonParameter", defaultValue: "Comparison", table: "Widgets"),
    default: WidgetCurrency("USD"), query: ComparisonCurrencyQuery()) var comparison: WidgetCurrency
  @Parameter(title: "Calculator", query: CalculatorInstanceQuery())
  var instance: CalculatorInstance?

  static var parameterSummary: some ParameterSummary {
    Summary {
      \.$base
      \.$comparison
    }
  }

  func specification(kind: String, location: WidgetLocation?) -> WidgetSpec {
    WidgetSpec(
      kind: kind,
      codes: [
        (base.id), (comparison.id == localCurrencyID ? "USD" : comparison.id)
      ],
      local: comparison.id == localCurrencyID,
      location: location, instanceID: instance?.id)
  }
}

struct AnchorSettings: SuiteConfiguration {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "pairSettings", defaultValue: "Currency pair", table: "Widgets")
  @Parameter(
    title: LocalizedStringResource("baseParameter", defaultValue: "Base", table: "Widgets"),
    default: WidgetCurrency("EUR"), query: BaseCurrencyQuery())
  var base: WidgetCurrency
  @Parameter(
    title: LocalizedStringResource(
      "comparisonParameter", defaultValue: "Comparison", table: "Widgets"),
    default: WidgetCurrency("USD"), query: ComparisonCurrencyQuery()) var comparison: WidgetCurrency

  func specification(kind: String, location: WidgetLocation?) -> WidgetSpec {
    WidgetSpec(
      kind: kind,
      codes: [
        (base.id), (comparison.id == localCurrencyID ? "USD" : comparison.id)
      ],
      local: comparison.id == localCurrencyID,
      location: location)
  }
}

struct CashSettings: SuiteConfiguration {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "cashSettings", defaultValue: "Know Your Cash settings", table: "Widgets")
  @Parameter(
    title: LocalizedStringResource("baseParameter", defaultValue: "Base", table: "Widgets"),
    default: CashCurrency("CZK"), query: CashBaseQuery())
  var base: CashCurrency
  @Parameter(
    title: LocalizedStringResource(
      "comparisonParameter", defaultValue: "Comparison", table: "Widgets"),
    default: CashCurrency("EUR"), query: CashComparisonQuery()) var comparison: CashCurrency
  @Parameter(title: "Calculator", query: CalculatorInstanceQuery())
  var instance: CalculatorInstance?

  static var parameterSummary: some ParameterSummary {
    Summary {
      \.$base
      \.$comparison
    }
  }

  func specification(kind: String, location: WidgetLocation?) -> WidgetSpec {
    let source = WidgetPresets.allows(base.id) ? (base.id) : "CZK"
    let target = WidgetPresets.allows(comparison.id) ? (comparison.id) : "EUR"
    return WidgetSpec(
      kind: kind, codes: [source, target],
      amount: NSDecimalNumber(decimal: WidgetPresets.amounts(source)[0]).stringValue,
      local: comparison.id == localCurrencyID, location: location, instanceID: instance?.id)
  }
}

struct BoardSettings: SuiteConfiguration {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "boardSettings", defaultValue: "Currency Board settings", table: "Widgets")
  @Parameter(
    title: LocalizedStringResource("baseParameter", defaultValue: "Base", table: "Widgets"),
    default: WidgetCurrency("EUR"), query: BaseCurrencyQuery())
  var base: WidgetCurrency
  @Parameter(
    title: LocalizedStringResource("amountParameter", defaultValue: "Amount", table: "Widgets"),
    description:
      LocalizedStringResource(
        "amountHelp",
        defaultValue:
          "A positive number, using a dot or comma for decimals, without grouping separators.",
        table: "Widgets"),
    default: "1") var amount: String
  @Parameter(
    title: LocalizedStringResource(
      "listModeParameter", defaultValue: "Currency list", table: "Widgets"), default: .selected)
  var list: BoardCurrencyList
  @Parameter(
    title: LocalizedStringResource(
      "currenciesParameter", defaultValue: "Currencies", table: "Widgets"),
    default: ["USD", "GBP", "CZK", "CHF", "JPY", "BTC"].map(WidgetCurrency.init),
    size: .init(min: 1, max: 12), query: BoardCurrencyQuery()) var currencies: [WidgetCurrency]?

  static var parameterSummary: some ParameterSummary {
    When(\.$list, .equalTo, BoardCurrencyList.selected) {
      Summary {
        \.$base; \.$amount; \.$list; \.$currencies
      }
    } otherwise: {
      Summary {
        \.$base; \.$amount; \.$list
      }
    }
  }

  func specification(kind: String, location: WidgetLocation?) -> WidgetSpec {
    WidgetSpec(
      kind: kind,
      codes: [(base.id)]
        + (list == .standard
          ? ["USD", "GBP", "CZK", "CHF", "JPY", "BTC"]
          : (currencies?.map(\.id) ?? ["USD", "GBP", "CZK", "CHF", "JPY", "BTC"])),
      amount: amount)
  }
}
