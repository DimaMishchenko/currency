import AppIntents
import CompanionSync
import Conversion
import CurrencyApplication
import CurrencyDetails
import ExchangeRates
import Foundation
import Home
import LocalCurrency
import WidgetKit

@MainActor
final class WatchComposition {
  private let directory: URL
  private var companion: CompanionSyncTransport?
  private(set) var companionIssue: CompanionSyncIssue?
  let conversion: ConversionStore
  let rates: RateStore
  let history: HistoryService
  private let service = RateService()
  private let discovery = HomeDiscoveryStore(defaults: .standard)
  private var issue: HomeIssue?
  private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]
  let systemActions: SystemActionComposition

  init() {
    guard
      let directory = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.dimasike.currency.shared")
    else { preconditionFailure("Currency Watch requires its App Group entitlement") }
    self.directory = directory
    conversion = ConversionStore(directory: directory)
    rates = RateStore(directory: directory)
    history = HistoryService(directory: directory)
    systemActions = SystemActionComposition(directory: directory)
    let actions = systemActions
    AppDependencyManager.shared.add(dependency: actions)
  }

  func startCompanionSync() {
    if companion == nil {
      do {
        let store = CompanionSyncStateStore(directory: directory)
        let engine = try CompanionSyncEngine(
          dependencies: .init(
            loadState: store.load, saveState: store.save,
            editInput: { [conversion] mutation in _ = try conversion.updateInput(mutation) },
            changed: { [weak self] in self?.changed() }))
        companion = CompanionSyncTransport(role: .watch, engine: engine)
      } catch { companionIssue = .commitFailed; return }
    }
    companion?.start()
    companion?.reconcile()
    companionIssue = companion?.issue
  }

  func changed() {
    for observer in observers.values { observer.yield(()) }
    WidgetCenter.shared.reloadAllTimelines()
  }

  func changes() -> AsyncStream<Void> {
    let id = UUID()
    return AsyncStream { continuation in
      observers[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor in self?.observers.removeValue(forKey: id) }
      }
    }
  }

  func edit(_ mutation: (inout ConverterState) throws -> Void) throws -> ConverterState {
    let input = try conversion.updateInput(mutation)
    changed()
    return input
  }

  func refresh(force: Bool) async throws -> RefreshResult {
    do {
      let result = try await rates.refreshRates(using: service, force: force)
      try Task.checkCancellation()
      issue = result.warning.map(HomeIssue.rateWarning)
      changed()
      return result
    } catch is CancellationError { throw CancellationError() } catch {
      try Task.checkCancellation()
      issue = .rateSaveFailed
      changed()
      throw error
    }
  }

  var home: HomeDependencies {
    .init(
      readInput: conversion.input, readRates: rates.loadRates,
      readRateIssue: { [self] in issue }, readLocalCurrency: { (nil, .notDetermined) },
      editInput: { [self] in try edit($0) },
      refreshRates: { [self] in try await refresh(force: $0) },
      changes: { [self] in changes() }, readDiscovery: { [discovery] in discovery.load() },
      saveDiscovery: { [discovery] in discovery.save($0) }, onboardingCompleted: { true },
      now: { .now })
  }

  var details: CurrencyDetailsDependencies {
    .init(loadHistory: { [history] in await history.load(base: $0, quote: $1, range: $2) })
  }
}

struct SystemActionComposition: Sendable {
  let action: ConversionAction
  let readSelected: @Sendable () -> [String]

  init(directory: URL) {
    let conversion = ConversionStore(directory: directory)
    let rates = RateStore(directory: directory)
    let service = RateService()
    readSelected = { [conversion] in
      let input = conversion.input()
      return [input.source] + input.manualDestinations
    }
    action = ConversionAction(
      dependencies: .init(
        readInput: conversion.input, readLocal: { (nil, .notDetermined) },
        readRates: rates.loadRates,
        refresh: { now in
          let result = try await rates.refreshRates(
            using: service, now: now, providerTimeout: .seconds(3))
          try Task.checkCancellation()
          WidgetCenter.shared.reloadAllTimelines()
          return result
        }))
  }
}
