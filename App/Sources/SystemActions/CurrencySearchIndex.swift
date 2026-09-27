import AppIntents
import Conversion
import CoreSpotlight
import CurrencyApplication
import ExchangeRates
import Foundation
import LocalCurrency
import OSLog

@MainActor
final class CurrencySearchIndex: NSObject, CSSearchableIndexDelegate {
  struct State: Equatable {
    var ids: [String]
    var observation: WidgetLocation?
    var status: WidgetLocationStatus
    var localeIdentifier = Locale.current.identifier
    var preferredLanguages = Locale.preferredLanguages
    var entities: [CurrencyEntity] {
      let permitted = status.allowsCache && observation?.isUsable == true ? observation : nil
      return ids.filter { $0 != CurrencySelection.localID || permitted != nil }
        .map { CurrencyEntity($0, local: $0 == CurrencySelection.localID ? permitted : nil) }
    }
  }
  struct Dependencies {
    let readState: @MainActor () -> State
    let delete: @MainActor () async throws -> Void
    let publish: @MainActor ([CurrencyEntity]) async throws -> Void
  }
  private let dependencies: Dependencies
  private let index: CSSearchableIndex?
  private static let domain = "Currency.Catalog"
  private static let logger = Logger(subsystem: "com.dimasike.currency", category: "Spotlight")
  static let indexName = "Currency.SelectedCurrencies"
  static let cleanupDomains = [indexName, domain]
  static let converterID = "Currency.Converter"
  static var converterItem: CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .content)
    attributes.title = String(localized: "Currency")
    attributes.contentDescription = String(localized: "Convert currencies, crypto and metals")
    attributes.keywords = [
      String(localized: "currency"), String(localized: "convert"), String(localized: "exchange"),
      String(localized: "currency converter"), String(localized: "exchange rate"),
      String(localized: "money"), String(localized: "crypto"), String(localized: "metals")
    ]
    attributes.textContent = attributes.keywords?.joined(separator: " ")
    attributes.contentURL = CurrencyRoute.converter.url
    return CSSearchableItem(
      uniqueIdentifier: converterID, domainIdentifier: domain, attributeSet: attributes)
  }
  private var worker: Task<Void, Never>?
  private var dirty = false
  private var forceRebuild = false
  private var lastPublishedState: State?
  private(set) var cleanupNeeded = true
  private var retryAttempt = 0
  private var retryTask: Task<Void, Never>?
  private var completions: [() -> Void] = []
  init(dependencies: Dependencies, index: CSSearchableIndex? = nil) {
    self.dependencies = dependencies; self.index = index
    super.init()
    index?.indexDelegate = self
  }
  static func live(composition: SystemActionComposition) -> CurrencySearchIndex {
    let index = CSSearchableIndex(name: indexName)
    let dependencies = Dependencies(
      readState: {
        let (observation, status) = composition.readLocal()
        return State(
          ids: CurrencyCatalog.codes + [CurrencySelection.localID], observation: observation,
          status: status)
      },
      delete: {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, Error>) in
          index.deleteSearchableItems(withDomainIdentifiers: cleanupDomains) { error in
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
          }
        }
      },
      publish: { entities in
        let items =
          entities.map { entity in
            let item = CSSearchableItem(appEntity: entity)
            item.domainIdentifier = domain
            return item
          } + [converterItem]
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, Error>) in
          index.indexSearchableItems(items) { error in
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
          }
        }
      })
    return CurrencySearchIndex(dependencies: dependencies, index: index)
  }
  func reconcile(force: Bool = false, completion: (() -> Void)? = nil) {
    retryTask?.cancel(); retryTask = nil; retryAttempt = 0
    start(force: force, completion: completion)
  }
  private func start(force: Bool = false, completion: (() -> Void)? = nil) {
    if let completion { completions.append(completion) }
    forceRebuild = forceRebuild || force
    dirty = true
    guard worker == nil else { return }
    worker = Task { [weak self] in
      guard let self else { return }
      while dirty {
        dirty = false
        let forced = forceRebuild
        forceRebuild = false
        if !forced && !cleanupNeeded && dependencies.readState() == lastPublishedState {
          continue
        }
        do {
          try await dependencies.delete()
          let state = dependencies.readState()
          try await dependencies.publish(state.entities)
          Self.logger.info("Indexed \(state.entities.count, privacy: .public) currency entities")
          lastPublishedState = state
          cleanupNeeded = false
          retryAttempt = 0
          if dependencies.readState() != state {
            cleanupNeeded = true
            dirty = true
          }
        } catch {
          cleanupNeeded = true
          Self.logger.error(
            "Currency indexing failed: \(error.localizedDescription, privacy: .public)")
          break
        }
      }
      worker = nil
      let callbacks = completions; completions = []
      callbacks.forEach { $0() }
      if cleanupNeeded && retryAttempt < 3 {
        retryAttempt += 1
        let delay = retryAttempt * 2
        retryTask = Task { [weak self] in
          do { try await Task.sleep(for: .seconds(delay)) } catch { return }
          guard let self else { return }
          retryTask = nil; start()
        }
      }
    }
  }
  func rebuild() async {
    await withCheckedContinuation { continuation in
      reconcile(force: true) { continuation.resume() }
    }
  }
  nonisolated func searchableIndex(
    _ searchableIndex: CSSearchableIndex,
    reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void
  ) {
    let acknowledgement = IndexAcknowledgement(acknowledgementHandler)
    Task { @MainActor in reconcile(force: true, completion: acknowledgement.call) }
  }
  nonisolated func searchableIndex(
    _ searchableIndex: CSSearchableIndex,
    reindexSearchableItemsWithIdentifiers identifiers: [String],
    acknowledgementHandler: @escaping () -> Void
  ) {
    let acknowledgement = IndexAcknowledgement(acknowledgementHandler)
    Task { @MainActor in reconcile(force: true, completion: acknowledgement.call) }
  }
}

private final class IndexAcknowledgement: @unchecked Sendable {
  private let handler: () -> Void
  init(_ handler: @escaping () -> Void) { self.handler = handler }
  func call() { handler() }
}
