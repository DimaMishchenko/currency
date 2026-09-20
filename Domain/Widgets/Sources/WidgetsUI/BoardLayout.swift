import Conversion
import DesignSystem
import ExchangeRatesUI
import LocalCurrency
import SwiftUI
import WidgetKit
import Widgets

/// The reference board rendered from the full canonical currency selection.
public struct BoardLayout: View {
  let family: WidgetFamily
  @Environment(\.locale) private var locale
  let entry: SuiteEntry

  /// Creates a small, medium, or large board.
  public init(family: WidgetFamily, entry: SuiteEntry) { self.family = family; self.entry = entry }

  private var base: String { entry.spec.codes.first ?? "EUR" }

  private var limit: Int { family == .systemSmall ? 4 : family == .systemMedium ? 6 : 12 }

  private var targets: [String] {
    var visible = Array(entry.spec.codes.prefix(limit))
    if let local = entry.spec.codes.first(where: WidgetSelection.isLocal), !visible.contains(local)
    {
      visible[visible.count - 1] = local
    }
    return visible
  }

  /// Currency rows, overflow information, and local-currency status.
  public var body: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
      if let amount = WidgetMath.parseAmount(entry.spec.amount) {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: AppStyle.Space.medium),
            count: family == .systemSmall ? 1 : 2),
          spacing: family == .systemLarge ? AppStyle.Space.large : AppStyle.Space.small
        ) {
          ForEach(targets, id: \.self) { selection in
            let code = WidgetSelection.currency(selection)
            if code == WidgetSelection.localID {
              LocalCurrencySetup(status: entry.spec.locationStatus, compact: true)
            } else {
              row(
                code: code,
                amount: CurrencyDisplay.format(
                  entry.snapshot.convert(amount, from: base, to: code), code: code, locale: locale),
                primary: selection == base, local: WidgetSelection.isLocal(selection))
            }
          }
        }
        Spacer(minLength: 0)
        if entry.spec.requiresCurrencySelection {
          Text(.WidgetPresentation.chooseCustomCurrencies).font(AppStyle.font(.caption2))
            .foregroundStyle(.secondary)
        }
        if entry.spec.codes.count > limit {
          Text(.WidgetPresentation.boardOverflow(entry.spec.codes.count - limit))
            .font(AppStyle.font(.caption2)).foregroundStyle(.secondary).lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        WidgetFooter(entry: entry)
      } else {
        Text(.WidgetPresentation.checkAmount).font(AppStyle.font(.headline))
        Text(.WidgetPresentation.invalidAmountHelp)
          .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
      }
    }
    .animation(nil, value: entry.spec.amount)
    .modifier(WidgetSurface())
  }

  private func row(
    code: String, amount: String, primary: Bool = false, local: Bool = false
  ) -> some View {
    HStack(spacing: AppStyle.Space.xs) {
      WidgetCurrencyIcon(code: code, size: 14, isLocal: local)
        .frame(width: 20, height: 20)
      Text(code).font(AppStyle.font(.caption2)).bold(primary)
      Spacer(minLength: 0)
      Text(amount)
        .font(AppStyle.font(.subheadline)).bold(primary).monospacedDigit()
    }
    .lineLimit(1).minimumScaleFactor(0.4)
  }
}
