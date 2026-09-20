import Conversion
import ExchangeRates
import Foundation
import WidgetKit

struct CurrencyEntry: TimelineEntry {
  let date: Date
  let input: ConverterState
  let snapshot: RateSnapshot
}

struct CurrencyTimeline: TimelineProvider {
  let dependencies: WidgetTimelineDependencies

  func placeholder(in context: Context) -> CurrencyEntry {
    CurrencyEntry(date: dependencies.now(), input: ConverterState(), snapshot: RateSnapshot())
  }

  func getSnapshot(in context: Context, completion: @escaping (CurrencyEntry) -> Void) {
    completion(
      CurrencyEntry(
        date: dependencies.now(), input: dependencies.input(), snapshot: dependencies.rates()))
  }

  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<CurrencyEntry>) -> Void
  ) {
    Task { completion(await loadTimeline()) }
  }

  /// The actual provider path, callable with controlled dependencies in integration tests.
  func loadTimeline() async -> Timeline<CurrencyEntry> {
    var snapshot = dependencies.rates()
    var refreshCompleted = true
    let input = dependencies.input()
    let now = dependencies.now()
    let recentlyTyped = now.timeIntervalSince(input.editedAt ?? .distantPast) < 60
    if !recentlyTyped
      && (snapshot.quotes.isEmpty
        || now.timeIntervalSince(snapshot.checkedAt ?? .distantPast) >= 1800)
    {
      let result = try? await dependencies.refreshRates(snapshot.quotes.isEmpty)
      refreshCompleted = result != nil
      snapshot = dependencies.rates()
    }
    return Timeline(
      entries: [
        CurrencyEntry(date: dependencies.now(), input: dependencies.input(), snapshot: snapshot)
      ],
      policy: .after(
        dependencies.now()
          .addingTimeInterval(
            !refreshCompleted || snapshot.quotes.isEmpty ? 300 : 1800)))
  }
}
