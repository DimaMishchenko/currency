import AppIntents
import CurrencySupport
import ExchangeRates
import Foundation
import WidgetPresentation

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
    title: "\(code)", subtitle: "\(CurrencyDisplay.name(code))",
    image: .init(systemName: "globe"))
}

private func currencySections<Entity: AppEntity>(
  allowsLocal: Bool = false, cashOnly: Bool = false, excluding: Set<String> = [],
  make: (String) -> Entity
) -> IntentItemCollection<Entity> {
  let allowed = CurrencyCatalog.codes.filter {
    !excluding.contains($0) && (!cashOnly || WidgetPresets.allows($0))
  }
  let selected = WidgetSelection.appCurrencies(CurrencyStore.shared.input())
    .filter(allowed.contains)
  let remaining = allowed.filter { !selected.contains($0) }.sorted()
  var sections: [IntentItemSection<Entity>] = []
  func append(_ title: LocalizedStringResource, _ codes: [String]) {
    if !codes.isEmpty { sections.append(IntentItemSection(title, items: codes.map(make))) }
  }
  append(
    LocalizedStringResource("appSelectedSection", defaultValue: "App selected", table: "Widgets"),
    selected)
  if allowsLocal && !excluding.contains(localCurrencyID) {
    append(
      LocalizedStringResource("locationSection", defaultValue: "Location", table: "Widgets"),
      [localCurrencyID])
  }
  append(
    LocalizedStringResource("fiatSection", defaultValue: "Currencies", table: "Widgets"),
    remaining.filter { !WidgetPresets.metals.contains($0) && !CurrencyCatalog.crypto.contains($0) })
  append(
    LocalizedStringResource("metalsSection", defaultValue: "Metals", table: "Widgets"),
    remaining.filter(WidgetPresets.metals.contains))
  append(
    LocalizedStringResource("cryptoSection", defaultValue: "Crypto", table: "Widgets"),
    remaining.filter(CurrencyCatalog.crypto.contains))
  return IntentItemCollection(sections: sections)
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

  func suggestedEntities() async throws -> IntentItemCollection<WidgetCurrency> {
    currencySections(make: WidgetCurrency.init)
  }

  func entities(matching string: String) async throws -> IntentItemCollection<WidgetCurrency> {
    IntentItemCollection(
      items: CurrencyCatalog.codes
        .filter {
          $0.localizedCaseInsensitiveContains(string)
            || CurrencyDisplay.name($0).localizedCaseInsensitiveContains(string)
        }
        .map(WidgetCurrency.init))
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

  func suggestedEntities() async throws -> IntentItemCollection<CashCurrency> {
    currencySections(cashOnly: true, make: CashCurrency.init)
  }

  func entities(matching string: String) async throws -> IntentItemCollection<CashCurrency> {
    IntentItemCollection(
      items: CurrencyCatalog.codes
        .filter {
          WidgetPresets.allows($0)
            && ($0.localizedCaseInsensitiveContains(string)
              || CurrencyDisplay.name($0).localizedCaseInsensitiveContains(string))
        }
        .map(CashCurrency.init))
  }
}

struct BaseCurrencyQuery: EntityStringQuery {
  func defaultResult() async -> WidgetCurrency? {
    WidgetCurrency("EUR")
  }
  func entities(for identifiers: [String]) async throws -> [WidgetCurrency] {
    try await CurrencyQuery().entities(for: identifiers)
  }
  func suggestedEntities() async throws -> IntentItemCollection<WidgetCurrency> {
    try await CurrencyQuery().suggestedEntities()
  }
  func entities(matching string: String) async throws -> IntentItemCollection<WidgetCurrency> {
    try await CurrencyQuery().entities(matching: string)
  }
}

struct CashBaseQuery: EntityStringQuery {
  func defaultResult() async -> CashCurrency? { CashCurrency("CZK") }
  func entities(for identifiers: [String]) async throws -> [CashCurrency] {
    try await CashQuery().entities(for: identifiers)
  }
  func suggestedEntities() async throws -> IntentItemCollection<CashCurrency> {
    try await CashQuery().suggestedEntities()
  }
  func entities(matching string: String) async throws -> IntentItemCollection<CashCurrency> {
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
  func suggestedEntities() async throws -> IntentItemCollection<WidgetCurrency> {
    currencySections(allowsLocal: true, make: WidgetCurrency.init)
  }
  func entities(matching string: String) async throws -> IntentItemCollection<WidgetCurrency> {
    let localName = String(
      localized: "localCurrencyChoice", defaultValue: "Local currency", table: "Widgets")
    let local =
      localName.localizedCaseInsensitiveContains(string) ? [WidgetCurrency(localCurrencyID)] : []
    return IntentItemCollection(
      items: local + (try await CurrencyQuery().entities(matching: string)).items)
  }
}

struct CashComparisonQuery: EntityStringQuery {
  func defaultResult() async -> CashCurrency? { CashCurrency("EUR") }

  func entities(for identifiers: [String]) async throws -> [CashCurrency] {
    identifiers.filter { $0 == localCurrencyID || WidgetPresets.allows($0) }.map(CashCurrency.init)
  }
  func suggestedEntities() async throws -> IntentItemCollection<CashCurrency> {
    currencySections(allowsLocal: true, cashOnly: true, make: CashCurrency.init)
  }
  func entities(matching string: String) async throws -> IntentItemCollection<CashCurrency> {
    let localName = String(
      localized: "localCurrencyChoice", defaultValue: "Local currency", table: "Widgets")
    let local =
      localName.localizedCaseInsensitiveContains(string) ? [CashCurrency(localCurrencyID)] : []
    return IntentItemCollection(
      items: local + (try await CashQuery().entities(matching: string)).items)
  }
}

/// WidgetKit asks queries for defaults when presenting its native editor.
struct MultiCurrencyQuery: EntityStringQuery {
  @IntentParameterDependency<MultiSettings> var settings: IntentProjection<MultiSettings>?

  init() { _settings = IntentParameterDependency(\.$list, \.$currencies) }

  private var selected: Set<String> { Set(settings?.currencies.map(\.id) ?? []) }

  func defaultResult() async -> [WidgetCurrency]? {
    guard settings?.list == .selected else { return nil }
    return WidgetSelection.appCurrencies(CurrencyStore.shared.input()).map(WidgetCurrency.init)
  }
  func entities(for identifiers: [String]) async throws -> [WidgetCurrency] {
    try await ComparisonCurrencyQuery()
      .entities(for: WidgetSelection.normalize(identifiers, allowsLocal: true))
  }
  func suggestedEntities() async throws -> IntentItemCollection<WidgetCurrency> {
    currencySections(allowsLocal: true, excluding: selected, make: WidgetCurrency.init)
  }
  func entities(matching string: String) async throws -> IntentItemCollection<WidgetCurrency> {
    IntentItemCollection(
      items: (try await ComparisonCurrencyQuery().entities(matching: string)).items
        .filter { !selected.contains($0.id) })
  }
}

struct BoardCurrencyQuery: EntityStringQuery {
  @IntentParameterDependency<BoardSettings> var settings: IntentProjection<BoardSettings>?

  init() { _settings = IntentParameterDependency(\.$list, \.$currencies) }

  private var selected: Set<String> { Set(settings?.currencies.map(\.id) ?? []) }

  func defaultResult() async -> [WidgetCurrency]? {
    guard settings?.list == .selected else { return nil }
    return WidgetSelection.appCurrencies(CurrencyStore.shared.input()).map(WidgetCurrency.init)
  }
  func entities(for identifiers: [String]) async throws -> [WidgetCurrency] {
    try await CurrencyQuery()
      .entities(for: WidgetSelection.normalize(identifiers, allowsLocal: false))
  }
  func suggestedEntities() async throws -> IntentItemCollection<WidgetCurrency> {
    currencySections(excluding: selected, make: WidgetCurrency.init)
  }
  func entities(matching string: String) async throws -> IntentItemCollection<WidgetCurrency> {
    IntentItemCollection(
      items: (try await CurrencyQuery().entities(matching: string)).items
        .filter { !selected.contains($0.id) })
  }
}

enum CalculatorCurrencyList: String, AppEnum {
  case selected, synchronized
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource(
      "listModeParameter", defaultValue: "Currency list", table: "Widgets"))
  static let caseDisplayRepresentations: [CalculatorCurrencyList: DisplayRepresentation] = [
    .selected: DisplayRepresentation(
      title: LocalizedStringResource("selectedList", defaultValue: "Custom list", table: "Widgets")),
    .synchronized: DisplayRepresentation(
      title: LocalizedStringResource("syncedList", defaultValue: "Default", table: "Widgets"))
  ]
}

/// A persisted configuration identity. Native default provisioning must be validated independently.
/// Never generate this ID in a timeline or view: that would reset the saved input on refresh.
struct CalculatorInstance: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Calculator"
  static let defaultQuery = CalculatorInstanceQuery()
  let id: String
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "Input") }

}

struct CalculatorInstanceQuery: EntityQuery {
  func defaultResult() async -> CalculatorInstance? {
    CalculatorInstance(id: UUID().uuidString)
  }
  func entities(for identifiers: [String]) async throws -> [CalculatorInstance] {
    identifiers.filter { UUID(uuidString: $0) != nil }.map { CalculatorInstance(id: $0) }
  }
  func suggestedEntities() async throws -> [CalculatorInstance] {
    []
  }
}

protocol SuiteConfiguration: WidgetConfigurationIntent {
  func specification(kind: String, location: WidgetLocation?) -> WidgetSpec
}

struct MultiSettings: SuiteConfiguration {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "multiSettings", defaultValue: "Multi-currency settings", table: "Widgets")
  @Parameter(
    title: LocalizedStringResource(
      "currenciesParameter", defaultValue: "Currencies", table: "Widgets"),
    size: .init(min: 1, max: 200), query: MultiCurrencyQuery()) var currencies: [WidgetCurrency]?
  @Parameter(
    title: LocalizedStringResource(
      "listModeParameter", defaultValue: "Currency list", table: "Widgets"),
    description: LocalizedStringResource(
      "calculatorListHelp",
      defaultValue:
        "Default follows your app currencies. Choose Custom list to edit a separate selection.",
      table: "Widgets"), default: .synchronized)
  var list: CalculatorCurrencyList
  @Parameter(
    title: LocalizedStringResource(
      "includeLocal", defaultValue: "Add local currency to Default", table: "Widgets"),
    default: false)
  var includeLocal: Bool
  @Parameter(title: "Calculator", query: CalculatorInstanceQuery())
  var instance: CalculatorInstance?

  static var parameterSummary: some ParameterSummary {
    Switch(.widgetFamily) {
      Case(.systemMedium) {
        When(\.$list, .equalTo, CalculatorCurrencyList.selected) {
          Summary(
            "Medium shows the first 4 currencies. Additional currencies appear on Large.",
            table: "Widgets"
          ) {
            \.$list; \.$currencies
          }
        } otherwise: {
          Summary(
            "Medium follows the first 4 app currencies. Local uses the last slot when enabled.",
            table: "Widgets"
          ) {
            \.$list; \.$includeLocal
          }
        }
      }
      DefaultCase {
        When(\.$list, .equalTo, CalculatorCurrencyList.selected) {
          Summary("Large shows the first 8 currencies. Medium shows the first 4.", table: "Widgets")
          {
            \.$list; \.$currencies
          }
        } otherwise: {
          Summary(
            "Large follows the first 8 app currencies. Local uses the last slot when enabled.",
            table: "Widgets"
          ) {
            \.$list; \.$includeLocal
          }
        }
      }
    }
  }

  func specification(kind: String, location: WidgetLocation?) -> WidgetSpec {
    let custom = list == .selected
    let codes = WidgetSelection.calculator(
      app: CurrencyStore.shared.input(),
      custom: currencies?.map(\.id), usesCustom: custom, includeLocal: includeLocal)
    var spec = WidgetSpec(kind: kind, codes: codes, location: location, instanceID: instance?.id)
    spec.synchronized = !custom
    spec.requiresCurrencySelection = custom && codes.isEmpty
    return spec
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
      "listModeParameter", defaultValue: "Currency list", table: "Widgets"), default: .synchronized)
  var list: CalculatorCurrencyList
  @Parameter(
    title: LocalizedStringResource(
      "currenciesParameter", defaultValue: "Currencies", table: "Widgets"),
    size: .init(min: 1, max: 200), query: BoardCurrencyQuery()) var currencies: [WidgetCurrency]?

  static var parameterSummary: some ParameterSummary {
    When(\.$list, .equalTo, CalculatorCurrencyList.selected) {
      Summary {
        \.$base; \.$amount; \.$list; \.$currencies
      }
    } otherwise: {
      Summary {
        \.$list
      }
    }
  }

  func specification(kind: String, location: WidgetLocation?) -> WidgetSpec {
    var spec = WidgetSpec(
      kind: kind,
      codes: WidgetSelection.board(
        base: list == .synchronized ? CurrencyStore.shared.input().source : base.id,
        targets: (list == .synchronized
          ? WidgetSelection.appCurrencies(CurrencyStore.shared.input())
          : (currencies?.map(\.id) ?? []))
      ),
      amount: list == .synchronized ? CurrencyStore.shared.input().amount : amount)
    spec.requiresCurrencySelection = list == .selected && (currencies?.isEmpty ?? true)
    return spec
  }
}
