import Conversion
import ExchangeRates
import Foundation
import LocalCurrency
import OSLog
import WidgetKit
import Widgets
import WidgetsUI

struct SuiteTimeline<Configuration: SuiteConfiguration>: AppIntentTimelineProvider {
  let kind: String
  let dependencies: WidgetTimelineDependencies

  func placeholder(in context: Context) -> SuiteEntry { entry(Configuration()) }

  func snapshot(for configuration: Configuration, in context: Context) async -> SuiteEntry {
    entry(configuration)
  }

  func timeline(
    for configuration: Configuration, in context: Context
  ) async -> Timeline<SuiteEntry> {
    await loadTimeline(configuration)
  }

  func loadTimeline(_ configuration: Configuration) async -> Timeline<SuiteEntry> {
    let current = entry(configuration)
    if dependencies.now().timeIntervalSince(current.input.editedAt ?? .distantPast) < 60 {
      return timeline(starting: current)
    }
    if current.spec.usesLocation { await dependencies.refreshLocalCurrency() }
    let result = try? await dependencies.refreshRates(current.snapshot.quotes.isEmpty)
    let refreshed = entry(configuration)
    return timeline(starting: refreshed, retry: result == nil || refreshed.snapshot.quotes.isEmpty)
  }

  func timeline(starting current: SuiteEntry, retry: Bool = false) -> Timeline<SuiteEntry> {
    var current = current
    current.openURL = dependencies.saveContext(
      current.snapshot, readoutInput(current), kind, dependencies.now())
    var entries = [current]
    if current.spec.usesLocation, current.spec.localCode != nil, !current.spec.localIsStale,
      let expiresAt = current.spec.localExpiresAt
    {
      var stale = current
      stale.date = expiresAt
      stale.spec.localIsStale = true
      if stale.date > current.date { entries.append(stale) }
    }
    return Timeline(
      entries: entries,
      policy: .after(
        dependencies.now().addingTimeInterval(retry ? 300 : dependencies.refreshInterval)))
  }

  private func readoutInput(_ entry: SuiteEntry) -> WidgetInput? {
    let codes = entry.spec.codes
    guard !codes.isEmpty else { return nil }
    let base = WidgetSelection.currency(codes.first ?? "EUR")
    switch kind {
    case "CurrencyBoard":
      guard WidgetMath.parseAmount(entry.spec.amount) != nil else { return nil }
      return WidgetInput(codes: codes, amount: entry.spec.amount, metalUnit: entry.input.metalUnit)
    case "CurrencyCash":
      let presets = WidgetPresets.amounts(base)
      let amount = presets.contains(entry.input.decimal) ? entry.input.decimal : presets[0]
      return WidgetInput(
        codes: codes, amount: NSDecimalNumber(decimal: amount).stringValue, metalUnit: .gram)
    case "CurrencyPocketRate":
      let target = WidgetSelection.currency(codes.last ?? "USD")
      let rate = entry.snapshot.convert(1, from: base, to: target, metalUnit: .gram)
      guard let amount = rate.flatMap({ WidgetMath.anchor(rate: $0) }) else { return nil }
      return WidgetInput(
        codes: codes, amount: NSDecimalNumber(decimal: amount).stringValue, metalUnit: .gram)
    case "CurrencyMentalMath":
      let target = WidgetSelection.currency(codes.last ?? "USD")
      guard
        let rate = entry.snapshot.convert(
          1, from: base, to: target, metalUnit: entry.input.metalUnit),
        WidgetMath.rule(rate: rate) != nil
      else { return nil }
      return WidgetInput(codes: codes, amount: "1", metalUnit: entry.input.metalUnit)
    default: return entry.input
    }
  }

  func entry(_ configuration: Configuration) -> SuiteEntry {
    let app = dependencies.input()
    let (location, status) = dependencies.localSnapshot()
    let spec = configuration.specification(
      kind: kind, input: app, location: location, status: status)
    #if DEBUG
      Logger(subsystem: "com.dimasike.currency", category: "WidgetConfiguration")
        .debug(
          "Timeline kind=\(kind, privacy: .public) instance=\(spec.instanceID ?? "nil", privacy: .public) key=\(spec.key, privacy: .public)"
        )
    #endif
    var input = dependencies.widgetInput(spec.key, spec.codes, spec.amount)
    let rates = dependencies.rates()
    if ["CurrencyConverter", "CurrencyBoard", "CurrencyMentalMath"].contains(spec.kind) {
      input.setMetalUnit(app.metalUnit)
    }
    if spec.synchronized { input.synchronize(with: app, snapshot: rates) }
    return SuiteEntry(date: dependencies.now(), spec: spec, input: input, snapshot: rates)
  }
}
