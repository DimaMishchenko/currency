import AppIntents
import Conversion
import CoreSpotlight
import CurrencyApplication
import ExchangeRates
import ExchangeRatesUI
import Foundation
import LocalCurrency
import UniformTypeIdentifiers

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
      title: "\(id == CurrencySelection.localID ? name : id + " · " + name)",
      subtitle: "\(resolvedLocalCode ?? (id == CurrencySelection.localID ? "" : id))",
      image: Self.image(for: id),
      synonyms: Self.aliases(id).map { LocalizedStringResource("\($0)") })
  }
  var attributeSet: CSSearchableItemAttributeSet {
    let attributes = defaultAttributeSet
    attributes.title = id == CurrencySelection.localID ? name : "\(id) · \(name)"
    attributes.contentDescription = String(localized: "Open currency details in Currency")
    attributes.keywords =
      [name]
      + (id == CurrencySelection.localID
        ? [resolvedLocalCode, localCountry].compactMap { $0 }
        : [id] + Self.aliases(id))
    attributes.displayName = attributes.title
    attributes.alternateNames = [name, id, id.lowercased()] + Self.aliases(id)
    attributes.textContent = ([id, id.lowercased(), name] + Self.aliases(id)).joined(separator: " ")
    attributes.thumbnailData = CurrencyIcon.pickerImageData(resolvedLocalCode ?? id)
    attributes.contentURL = CurrencyRoute.currency(id).url
    return attributes
  }
  static func image(for id: String) -> DisplayRepresentation.Image? {
    if id == CurrencySelection.localID { return .init(systemName: "location.fill") }
    guard let data = CurrencyIcon.pickerImageData(id) else { return nil }
    return .init(data: data, isTemplate: false)
  }
  static func aliases(_ code: String) -> [String] {
    switch CurrencyCode(rawValue: code) {
    case .usd:
      [
        String(localized: "US dollar"), String(localized: "American dollar"),
        String(localized: "dollar"), "$"
      ]
    case .cad: [String(localized: "Canadian dollar"), String(localized: "dollar"), "$"]
    case .aud: [String(localized: "Australian dollar"), String(localized: "dollar"), "$"]
    case .nzd: [String(localized: "New Zealand dollar"), String(localized: "dollar"), "$"]
    case .eur: [String(localized: "euro"), "€"]
    case .gbp: [String(localized: "pound"), String(localized: "sterling"), "£"]
    case .jpy: [String(localized: "yen"), "¥"]
    case .cny: [String(localized: "yuan"), String(localized: "renminbi"), "¥"]
    default: []
    }
  }
}

struct CurrencyEntityQuery: EntityStringQuery, EnumerableEntityQuery {
  static let findIntentDescription: IntentDescription? = IntentDescription(
    "Find currencies to use in another action.")
  @AppDependency private var composition: SystemActionComposition
  @AppDependency private var searchIndex: CurrencySearchIndex
  let allowsLocal: Bool
  init() { self.init(allowsLocal: true) }
  init(allowsLocal: Bool) { self.allowsLocal = allowsLocal }
  private var allowed: [String] {
    let selected = composition.readSelected()
    let catalog =
      selected + CurrencyCatalog.codes + (allowsLocal ? [CurrencySelection.localID] : [])
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
    allowed.map(make)
  }
  func allEntities() async throws -> [CurrencyEntity] { allowed.map(make) }
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
