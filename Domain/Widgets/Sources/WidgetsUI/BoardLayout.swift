import Conversion
import DesignSystem
import ExchangeRates
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

  private var limit: Int { family == .systemSmall ? 6 : family == .systemMedium ? 12 : 24 }

  private var targets: [String] {
    var visible = Array(entry.spec.codes.prefix(limit))
    if let local = entry.spec.codes.first(where: WidgetSelection.isLocal), !visible.contains(local)
    {
      visible[visible.count - 1] = local
    }
    return visible
  }

  /// Currency rows and actionable configuration or local-currency status.
  public var body: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
      if let amount = WidgetMath.parseAmount(entry.spec.amount) {
        GeometryReader { geometry in
          let columns = family == .systemSmall ? 1 : 2
          let rows = (targets.count + columns - 1) / columns
          let rowHeight = geometry.size.height / CGFloat(max(1, rows))
          LazyVGrid(
            columns: Array(
              repeating: GridItem(.flexible(), spacing: AppStyle.Space.medium), count: columns),
            spacing: 0
          ) {
            ForEach(targets, id: \.self) { selection in
              let code = WidgetSelection.currency(selection)
              Group {
                if code == WidgetSelection.localID {
                  LocalCurrencySetup(status: entry.spec.locationStatus, compact: true)
                } else {
                  row(
                    code: code,
                    amount: CurrencyDisplay.format(
                      entry.snapshot.convert(
                        amount, from: base, to: code, metalUnit: entry.input.metalUnit), code: code,
                      locale: locale, metalUnit: entry.input.metalUnit),
                    primary: selection == base, local: WidgetSelection.isLocal(selection))
                }
              }
              .frame(height: rowHeight)
            }
          }
        }
        if entry.spec.requiresCurrencySelection {
          Text(.WidgetPresentation.chooseCustomCurrencies).font(AppStyle.font(.caption2))
            .foregroundStyle(.secondary)
        }
        WidgetFooter(entry: entry)
      } else {
        Text(.WidgetPresentation.checkAmount).font(AppStyle.font(.headline))
        Text(.WidgetPresentation.invalidAmountHelp)
          .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
      }
    }
    .animation(nil, value: entry.spec.amount)
    .modifier(
      WidgetSurface(
        openURL: entry.openURL,
        maximumTypeSize: targets.count > (family == .systemSmall ? 4 : 8) ? .xLarge : .xxxLarge))
  }

  private func row(
    code: String, amount: String, primary: Bool = false, local: Bool = false
  ) -> some View {
    HStack(spacing: AppStyle.Space.xs) {
      WidgetCurrencyIcon(code: code, size: 14, isLocal: local)
        .frame(width: 20, height: 20)
      Text(
        code
          + (CurrencyCode(rawValue: code)?.isMetal == true
            ? " · " + entry.input.metalUnit.symbol : "")
      )
      .font(AppStyle.font(.caption2)).bold(primary)
      Spacer(minLength: 0)
      Text(amount)
        .font(AppStyle.font(.subheadline)).bold(primary).monospacedDigit()
    }
    .lineLimit(1).minimumScaleFactor(0.4)
  }
}
