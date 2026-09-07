import CurrencySupport
import SwiftUI
import WidgetKit

struct BoardView: View {
  @Environment(\.widgetFamily) private var family
  let entry: SuiteEntry

  var body: some View { BoardLayout(family: family, entry: entry) }
}

struct BoardLayout: View {
  let family: WidgetFamily
  @Environment(\.locale) private var locale
  let entry: SuiteEntry

  private var base: String { entry.spec.codes.first ?? "EUR" }

  private var limit: Int { family == .systemSmall ? 4 : family == .systemMedium ? 6 : 12 }

  private var targets: [String] { Array(entry.spec.codes.prefix(limit)) }

  var body: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
      if let amount = WidgetMath.parseAmount(entry.spec.amount) {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: AppStyle.Space.medium),
            count: family == .systemSmall ? 1 : 2),
          spacing: family == .systemLarge ? AppStyle.Space.large : AppStyle.Space.small
        ) {
          ForEach(targets, id: \.self) { code in
            row(
              code: code,
              amount: CurrencyDisplay.format(
                entry.snapshot.convert(amount, from: base, to: code), code: code, locale: locale),
              primary: code == base)
          }
        }
        Spacer(minLength: 0)
        if entry.spec.requiresCurrencySelection {
          Text(.Widgets.chooseCustomCurrencies).font(AppStyle.font(.caption2))
            .foregroundStyle(.secondary)
        }
        if entry.spec.codes.count > limit {
          Text(.Widgets.boardOverflow(entry.spec.codes.count - limit))
            .font(AppStyle.font(.caption2)).foregroundStyle(.secondary).lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        WidgetFooter(entry: entry)
      } else {
        Text(.Widgets.checkAmount).font(AppStyle.font(.headline))
        Text(.Widgets.invalidAmountHelp)
          .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
      }
    }
    .animation(nil, value: entry.spec.amount)
    .modifier(WidgetSurface())
  }

  private func row(code: String, amount: String, primary: Bool = false) -> some View {
    HStack(spacing: AppStyle.Space.xs) {
      CurrencyIcon(code, size: 14)
        .frame(width: 20, height: 20)
      Text(code).font(AppStyle.font(.caption2)).bold(primary)
      Spacer(minLength: 0)
      Text(amount)
        .font(AppStyle.font(.subheadline)).bold(primary).monospacedDigit()
    }
    .lineLimit(1).minimumScaleFactor(0.4)
  }
}

struct CurrencyBoardWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyBoard", intent: BoardSettings.self,
      provider: SuiteTimeline<BoardSettings>(kind: "CurrencyBoard")
    ) { BoardView(entry: $0) }
    .configurationDisplayName(Text(.Widgets.board))
    .description(Text(.Widgets.newBoardDescription))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
