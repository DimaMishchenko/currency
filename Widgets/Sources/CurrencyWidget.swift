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
struct CurrencyWidgetView: View {
  @Environment(\.locale) private var locale
  let entry: CurrencyEntry
  var board = false
  @Environment(\.widgetFamily) private var family
  private var limit: Int {
    family == .systemSmall
      ? 1 : board ? (family == .systemLarge ? 12 : 6) : (family == .systemLarge ? 8 : 3)
  }
  private var targets: [String] { Array(entry.input.destinations.prefix(limit)) }
  private var columns: Int { (board || family == .systemLarge) && targets.count > 3 ? 2 : 1 }
  private var keyHeight: CGFloat { targets.count > 6 ? 36 : 42 }
  var body: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.small) {
      HStack {
        HStack(spacing: AppStyle.Space.xs) {
          CurrencyIcon(entry.input.source, size: 16)
          Text(verbatim: entry.input.source)
        }
        .font(AppStyle.font(.caption).weight(.semibold))
        Spacer()
        if family != .systemSmall {
          Text(CurrencyDisplay.inputAmount(entry.input.amount, locale: locale))
            .font(AppStyle.font(.title3, weight: .medium))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        }
      }
      if family == .systemSmall {
        Text(CurrencyDisplay.inputAmount(entry.input.amount, locale: locale))
          .font(AppStyle.font(.title2, weight: .light))
          .lineLimit(1).minimumScaleFactor(0.4)
      }
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: AppStyle.Space.large), count: columns),
        spacing: board ? AppStyle.Space.small : AppStyle.Space.xs
      ) {
        ForEach(targets, id: \.self) { code in
          HStack {
            HStack(spacing: AppStyle.Space.xs) {
              CurrencyIcon(code, size: 16)
              Text(verbatim: code)
            }
            .font(AppStyle.font(columns == 2 ? .caption2 : .caption, weight: .medium))
            Spacer(minLength: AppStyle.Space.xs)
            Text(
              CurrencyDisplay.format(
                entry.snapshot.convert(entry.input.decimal, from: entry.input.source, to: code),
                code: code, locale: locale)
            )
            .font(AppStyle.font(columns == 2 ? .subheadline : .title3, weight: .medium))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
            .contentTransition(.numericText())
          }
          .frame(minHeight: board && family == .systemLarge ? 28 : 22)
        }
      }
      Spacer(minLength: 0)
      HStack {
        Text(
          entry.snapshot.quotes.isEmpty
            ? .Widgets.openToLoad
            : .Widgets.ratesDate(
              entry.snapshot.quotes[targets.first ?? entry.input.source]
                .map { CurrencyDisplay.publicationDate($0.published, locale: locale) }
                ?? String(localized: .Widgets.unavailable))
        )
        .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        if entry.input.destinations.count > limit {
          Text(.Widgets.additionalCurrencies(entry.input.destinations.count - limit))
            .font(AppStyle.font(.caption2))
            .foregroundStyle(.secondary)
        }
      }
      if family == .systemLarge && !board {
        Grid(horizontalSpacing: AppStyle.Space.xs, verticalSpacing: AppStyle.Space.xs) {
          ForEach(
            [
              ["1", "2", "3", "AC"], ["4", "5", "6", "⌫"], ["7", "8", "9", "⇅"],
              [".", "0", "00", "open"]
            ], id: \.self
          ) { row in
            GridRow {
              ForEach(row, id: \.self) { key in
                if key == "open" {
                  if let destination = URL(string: "currency://convert") {
                    Link(destination: destination) {
                      Image(systemName: "arrow.up.right").frame(maxWidth: .infinity)
                        .frame(height: keyHeight)
                        .background(.primary.opacity(0.055), in: .rect(cornerRadius: 10))
                    }
                    .accessibilityLabel(Text(.Widgets.openApp))
                  }
                } else {
                  Button(intent: KeypadIntent(key)) {
                    Text(
                      key == "AC"
                        ? String(localized: .Widgets.clearKey)
                        : CurrencyDisplay.inputAmount(key, locale: locale)
                    )
                    .font(AppStyle.font(key == "AC" ? .caption : .title3))
                    .frame(maxWidth: .infinity).frame(height: keyHeight)
                    .background(.primary.opacity(0.055), in: .rect(cornerRadius: 10))
                    .contentShape(Rectangle())
                  }
                  .accessibilityLabel(
                    key == "⌫"
                      ? Text(.Widgets.delete)
                      : key == "AC"
                        ? Text(.Widgets.clear)
                        : key == "⇅"
                          ? Text(.Widgets.swap)
                          : key == "."
                            ? Text(.Widgets.decimalSeparator) : Text(verbatim: key))
                }
              }
            }
          }
        }
        .buttonStyle(.plain)
      }
    }
    .tint(Color(uiColor: .label))
    .containerBackground(for: .widget) { Color(.systemBackground) }
    .widgetURL(URL(string: "currency://convert"))
  }
}
struct CurrencyWidget: Widget {
  let kind = "CurrencyConverter"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: CurrencyTimeline()) { CurrencyWidgetView(entry: $0) }
      .configurationDisplayName(Text(.Widgets.converter))
      .description(Text(.Widgets.converterDescription))
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct CurrencyBoardWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CurrencyBoard", provider: CurrencyTimeline()) {
      CurrencyWidgetView(entry: $0, board: true)
    }
    .configurationDisplayName(Text(.Widgets.board))
    .description(Text(.Widgets.boardDescription))
    .supportedFamilies([.systemMedium, .systemLarge])
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
            CurrencyDisplay.inputAmount(entry.input.amount, locale: locale), entry.input.source,
            amount, target))
      } else {
        VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
          Text(
            .Widgets.conversionPair(
              CurrencyDisplay.inputAmount(entry.input.amount, locale: locale), entry.input.source,
              target)
          )
          .font(AppStyle.font(.caption))
          Text(amount).font(AppStyle.font(.title2, weight: .semibold))
            .minimumScaleFactor(0.4)
          Text(

            .Widgets.ratesDate(
              entry.snapshot.quotes[target]
                .map { CurrencyDisplay.publicationDate($0.published, locale: locale) }
                ?? String(localized: .Widgets.openApp))
          )
          .font(AppStyle.font(.caption2))
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
    CurrencyWidget()
    CurrencyBoardWidget()
    QuickRateWidget()
  }
}
