import AppIntents
import Conversion
import CoreSpotlight
import CurrencyApplication
import ExchangeRates
import ExchangeRatesUI
import Foundation
import LocalCurrency
import UniformTypeIdentifiers

/// App-owned currency content and calculation parameters; widget entities remain unchanged.
struct CurrencyEntity: IndexedEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Currency"
  static let defaultQuery = CurrencyEntityQuery()
  let id: String
  var resolvedLocalCode: String?
  var localCountry: String?
  init(_ id: String, local: WidgetLocation? = nil) {
    self.id = id; resolvedLocalCode = local?.currency; localCountry = local?.country
  }
  var name: String {
    id == CurrencySelection.localID ? String(localized: "Local currency") : CurrencyDisplay.name(id)
  }
  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(name)",
      subtitle: "\(resolvedLocalCode ?? (id == CurrencySelection.localID ? "" : id))",
      image: .init(
        systemName: id == CurrencySelection.localID ? "location.fill" : "dollarsign.circle"))
  }
  var attributeSet: CSSearchableItemAttributeSet {
    let attributes = CSSearchableItemAttributeSet(contentType: .content)
    attributes.title = id == CurrencySelection.localID ? name : "\(id) · \(name)"
    attributes.contentDescription = String(localized: "Open currency details in Currency")
    attributes.keywords =
      [name]
      + (id == CurrencySelection.localID
        ? [resolvedLocalCode, localCountry].compactMap { $0 }
        : [id] + Self.aliases(id))
    attributes.contentURL = CurrencyRoute.currency(id).url
    return attributes
  }
  static func aliases(_ code: String) -> [String] {
    switch code {
    case "USD": ["US dollar", "American dollar", "dollar", "$"]
    case "CAD": ["Canadian dollar", "dollar", "$"]
    case "AUD": ["Australian dollar", "dollar", "$"]
    case "NZD": ["New Zealand dollar", "dollar", "$"]
    case "EUR": ["euro", "€"]
    case "GBP": ["pound", "sterling", "£"]
    case "JPY": ["yen", "¥"]
    case "CNY": ["yuan", "renminbi", "¥"]
    default: []
    }
  }
}

struct CurrencyEntityQuery: EntityStringQuery {
  @AppDependency private var composition: SystemActionComposition
  @AppDependency private var searchIndex: CurrencySearchIndex
  let allowsLocal: Bool
  let selectedOnly: Bool
  init() { self.init(allowsLocal: true, selectedOnly: false) }
  init(allowsLocal: Bool = true, selectedOnly: Bool = false) {
    self.allowsLocal = allowsLocal; self.selectedOnly = selectedOnly
  }
  private var allowed: [String] {
    let selected = composition.readSelected()
    let catalog =
      selectedOnly
      ? selected
      : selected + CurrencyCatalog.codes.sorted() + (allowsLocal ? [CurrencySelection.localID] : [])
    var seen = Set<String>()
    return catalog.filter {
      (allowsLocal || $0 != CurrencySelection.localID) && seen.insert($0).inserted
    }
  }
  private func make(_ id: String) -> CurrencyEntity {
    guard id == CurrencySelection.localID else { return CurrencyEntity(id) }
    let (local, status) = composition.readLocal()
    return CurrencyEntity(
      id, local: status.allowsCache && local?.isUsable == true ? local : nil)
  }
  func entities(for identifiers: [String]) async throws -> [CurrencyEntity] {
    let allowed = Set(allowed)
    return identifiers.filter(allowed.contains).map(make)
  }
  func suggestedEntities() async throws -> [CurrencyEntity] {
    composition.readSelected().filter { allowsLocal || $0 != CurrencySelection.localID }.map(make)
  }
  func entities(matching string: String) async throws -> [CurrencyEntity] {
    let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let entities = allowed.map(make)
    let exact = entities.filter {
      $0.id.lowercased() == text.lowercased() || $0.name.lowercased() == text.lowercased()
    }
    if !exact.isEmpty { return exact }
    return entities.filter { entity in
      ([entity.name, entity.id] + CurrencyEntity.aliases(entity.id))
        .contains {
          $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .contains(text)
        }
    }
  }
  @available(iOS 27.0, *)
  func reindexEntities(
    for identifiers: [String], indexDescription: CSSearchableIndexDescription
  ) async throws {
    await searchIndex.rebuild()
  }
  @available(iOS 27.0, *)
  func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
    await searchIndex.rebuild()
  }
}

@available(iOS 27.0, *)
extension CurrencyEntityQuery: IndexedEntityQuery {}
