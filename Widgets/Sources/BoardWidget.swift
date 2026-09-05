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

  private var limit: Int { family == .systemSmall ? 3 : family == .systemMedium ? 6 : 12 }

  private var targets: [String] { Array(entry.spec.codes.dropFirst().prefix(limit)) }

  var body: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
      if let amount = WidgetMath.parseAmount(entry.spec.amount) {
        if family == .systemSmall {
          row(
            code: base, amount: CurrencyDisplay.format(amount, code: base, locale: locale),
            primary: true)
        } else {
          HStack {
            CurrencyIcon(base, size: 18)
            Text("\(CurrencyDisplay.format(amount, code: base, locale: locale)) \(base)")
              .font(AppStyle.font(.headline)).lineLimit(1).minimumScaleFactor(0.4)
            Spacer(minLength: 0)
          }
        }
        Divider()
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
                entry.snapshot.convert(amount, from: base, to: code), code: code, locale: locale))
          }
        }
        Spacer(minLength: 0)
        if entry.spec.codes.count - 1 > limit {
          Text(.Widgets.boardOverflow(entry.spec.codes.count - 1 - limit))
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
