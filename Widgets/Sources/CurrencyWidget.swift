import AppIntents
import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit

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
      let input = CurrencyStore.shared.input()
      let recentlyTyped = Date().timeIntervalSince(input.editedAt ?? .distantPast) < 60
      if !recentlyTyped && Date().timeIntervalSince(snapshot.checkedAt ?? .distantPast) >= 1800 {
        let refreshed = try? await CurrencyStore.shared.refreshRates(using: RateService())
        snapshot = refreshed?.snapshot ?? CurrencyStore.shared.loadRates()
      }
      completion(
        Timeline(
          entries: [
            CurrencyEntry(date: .now, input: CurrencyStore.shared.input(), snapshot: snapshot)
          ],
          policy: .after(.now.addingTimeInterval(1800))))
    }
  }
}

struct QuickRateView: View {
  @Environment(\.locale) private var locale
  let entry: CurrencyEntry
  @Environment(\.widgetFamily) private var family
  private var target: String { entry.input.destinations.first ?? entry.input.source }

  private var amount: String {
    CurrencyDisplay.format(
      entry.snapshot.convert(entry.input.decimal, from: entry.input.source, to: target),
      code: target, locale: locale)
  }

  var body: some View {
    Group {
      if family == .accessoryInline {
        Text(

          .Widgets.inlineConversion(
            CurrencyDisplay.inputAmount(entry.input.amount, locale: locale),
            CurrencyDisplay.flag(entry.input.source) + " " + entry.input.source,
            amount, CurrencyDisplay.flag(target) + " " + target))
      } else {
        VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
          HStack(spacing: AppStyle.Space.xs) {
            CurrencyIcon(entry.input.source, size: 16)
            Text(
              "\(CurrencyDisplay.inputAmount(entry.input.amount, locale: locale)) \(entry.input.source)"
            )
          }
          .font(AppStyle.font(.caption))
          HStack(spacing: AppStyle.Space.xs) {
            CurrencyIcon(target, size: 16)
            Text("\(amount) \(target)").font(AppStyle.font(.title2, weight: .semibold))
              .minimumScaleFactor(0.4)
          }
        }
      }
    }
    .lineLimit(1).tint(Color(uiColor: .label))
    .containerBackground(for: .widget) { Color.clear }
    .widgetURL(URL(string: "currency://convert"))
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
    PairCalculatorWidget()
    CashWidget()
    PocketRateWidget()
    MentalMathWidget()
    CurrencyBoardWidget()
    QuickRateWidget()
  }
}
