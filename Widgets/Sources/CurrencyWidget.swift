import AppIntents
import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit
import WidgetPresentation

struct CurrencyEntry: TimelineEntry {
  let date: Date
  let input: ConverterState
  let snapshot: RateSnapshot
}

struct CurrencyTimeline: TimelineProvider {
  func placeholder(in context: Context) -> CurrencyEntry {
    CurrencyEntry(date: .now, input: ConverterState(), snapshot: RateSnapshot())
  }

  func getSnapshot(in context: Context, completion: @escaping (CurrencyEntry) -> Void) {
    completion(
      CurrencyEntry(
        date: .now, input: CurrencyStore.shared.input(), snapshot: CurrencyStore.shared.loadRates()
      ))
  }

  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<CurrencyEntry>) -> Void
  ) {
    Task {
      var snapshot = CurrencyStore.shared.loadRates()
      var refreshCompleted = true
      let input = CurrencyStore.shared.input()
      let recentlyTyped = Date().timeIntervalSince(input.editedAt ?? .distantPast) < 60
      if !recentlyTyped
        && (snapshot.quotes.isEmpty
          || Date().timeIntervalSince(snapshot.checkedAt ?? .distantPast) >= 1800)
      {
        let result = try? await CurrencyStore.shared.refreshRates(
          using: RateService(), force: snapshot.quotes.isEmpty, providerTimeout: .seconds(2))
        refreshCompleted = result != nil
        snapshot = CurrencyStore.shared.loadRates()
      }
      completion(
        Timeline(
          entries: [
            CurrencyEntry(date: .now, input: CurrencyStore.shared.input(), snapshot: snapshot)
          ],
          policy: .after(
            .now.addingTimeInterval(
              !refreshCompleted || snapshot.quotes.isEmpty ? 300 : 1800))))
    }
  }
}

struct QuickRateView: View {
  @Environment(\.widgetFamily) private var family
  let entry: CurrencyEntry
  var body: some View {
    QuickRateLayout(input: entry.input, snapshot: entry.snapshot, family: family)
  }
}

struct QuickRateWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CurrencyQuickRate", provider: CurrencyTimeline()) {
      QuickRateView(entry: $0)
    }
    .configurationDisplayName(Text(.Widgets.quickRate))
    .description(Text(.Widgets.quickRateDescription))
    .supportedFamilies([.accessoryInline, .accessoryRectangular])
  }
}

@main struct CurrencyWidgets: WidgetBundle {
  var body: some Widget {
    MultiCurrencyWidget()
    CashWidget()
    PocketRateWidget()
    MentalMathWidget()
    CurrencyBoardWidget()
    QuickRateWidget()
  }
}
