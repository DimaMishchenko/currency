import CurrencySupport
import SwiftUI
import WidgetKit

struct CashView: View {
  @Environment(\.locale) private var locale
  let entry: SuiteEntry

  private var base: String { entry.spec.codes.first ?? "EUR" }

  private var target: String { entry.spec.codes.last ?? "USD" }

  private var presets: [Decimal] { WidgetPresets.amounts(base) }

  private var amount: Decimal {
    presets.contains(entry.input.decimal) ? entry.input.decimal : presets[0]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.small) {
      HStack {
        CurrencyIcon(base, size: 22)
        Text(base).font(AppStyle.font(.caption, weight: .medium))
        Spacer()
        Text(target).font(AppStyle.font(.caption, weight: .medium))
        CurrencyIcon(target, size: 22)
      }
      HStack(alignment: .firstTextBaseline, spacing: AppStyle.Space.small) {
        Text(label(amount)).font(AppStyle.font(.largeTitle, weight: .medium))
        Spacer(minLength: 0)
        Text(
          "≈ "
            + CurrencyDisplay.format(
              WidgetPresets.convert(amount, from: base, to: target, snapshot: entry.snapshot),
              code: target, locale: locale) + (WidgetPresets.metals.contains(target) ? " g" : "")
        )
        .font(AppStyle.font(.title, weight: .medium))
      }
      .lineLimit(1).minimumScaleFactor(0.4).monospacedDigit()
      Text(
        WidgetPresets.metals.contains(base)
          ? .Widgets.metalEstimate
          : WidgetPresets.isBanknote(base)
            ? .Widgets.banknoteEstimate : .Widgets.genericEstimate
      )
      .font(AppStyle.font(.caption2)).foregroundStyle(.secondary).lineLimit(1)
      .minimumScaleFactor(0.7)
      HStack(spacing: AppStyle.Space.xs) {
        ForEach(presets, id: \.self) { preset in
          Button(
            intent: WidgetAction(
              "preset:" + NSDecimalNumber(decimal: preset).stringValue, spec: entry.spec)
          ) {
            Text(label(preset)).font(AppStyle.font(.subheadline, weight: .medium))
              .lineLimit(1).minimumScaleFactor(0.6)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(
                .primary.opacity(
                  preset == amount ? AppStyle.Widget.selectedFill : AppStyle.Widget.tileFill),
                in: .rect(cornerRadius: AppStyle.Widget.keyRadius)
              )
              .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Widget.keyRadius)
                  .strokeBorder(
                    .primary.opacity(preset == amount ? AppStyle.Widget.selectedBorder : 0),
                    lineWidth: 1)
              }
          }
          .buttonStyle(.plain).accessibilityAddTraits(preset == amount ? .isSelected : [])
        }
      }
      .frame(minHeight: 28)
      WidgetFooter(entry: entry)
    }
    .modifier(WidgetSurface())
  }

  private func label(_ value: Decimal) -> String {
    if WidgetPresets.metals.contains(base) {
      return value == 1000
        ? "1 kg" : CurrencyDisplay.format(value, code: base, locale: locale) + " g"
    }
    return CurrencyDisplay.format(value, code: base, locale: locale)
  }
}

struct AnchorView: View {
  @Environment(\.locale) private var locale
  let entry: SuiteEntry
  var mental = false

  private var base: String { entry.spec.codes.first ?? "EUR" }

  private var target: String { entry.spec.codes.last ?? "USD" }

  var body: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
      if mental { Spacer(minLength: 0) }
      if let rate = entry.snapshot.convert(1, from: base, to: target), rate > 0 {
        if mental, let rule = WidgetMath.rule(rate: rate) {
          HStack(spacing: AppStyle.Space.xs) {
            CurrencyIcon(base, size: 20); Text(base)
          }
          .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
          Text(rule.divide ? .Widgets.divideBy : .Widgets.multiplyBy)
            .font(AppStyle.font(.subheadline))
            .lineLimit(1).minimumScaleFactor(0.6)
          Text(CurrencyDisplay.format(rule.factor, code: "BTC", locale: locale))
            .font(AppStyle.font(.largeTitle)).lineLimit(1).minimumScaleFactor(0.4)
          HStack(spacing: AppStyle.Space.xs) {
            CurrencyIcon(target, size: 20); Text("≈ \(target)")
          }
          .foregroundStyle(.secondary)
        } else if let anchor = WidgetMath.anchor(rate: rate) {
          VStack(spacing: AppStyle.Space.xs) {
            pocketRow(
              code: base, amount: CurrencyDisplay.format(anchor, code: base, locale: locale))
            Divider()
            pocketRow(
              code: target,
              amount: "≈ " + CurrencyDisplay.format(anchor * rate, code: target, locale: locale))
          }
        }
      } else {
        Text(.Widgets.openToLoad).font(AppStyle.font(.headline))
      }
      if mental { Spacer(minLength: 0) }
      WidgetFooter(entry: entry)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .lineLimit(1).minimumScaleFactor(0.4)
    .modifier(WidgetSurface())
  }

  private func pocketRow(code: String, amount: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: AppStyle.Space.xs) {
        CurrencyIcon(code, size: 16).frame(width: 20, height: 20)
        Text(code).font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
      }
      Text(amount).font(AppStyle.font(.title)).monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

}

struct CashWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyCash", intent: CashSettings.self,
      provider: SuiteTimeline<CashSettings>(kind: "CurrencyCash")
    ) { CashView(entry: $0) }
    .configurationDisplayName(Text(.Widgets.cashTitle))
    .description(Text(.Widgets.cashDescription))
    .supportedFamilies([.systemMedium])
  }
}

struct PocketRateWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyPocketRate", intent: AnchorSettings.self,
      provider: SuiteTimeline<AnchorSettings>(kind: "CurrencyPocketRate")
    ) { AnchorView(entry: $0) }
    .configurationDisplayName(Text(.Widgets.pocketTitle))
    .description(Text(.Widgets.pocketDescription))
    .supportedFamilies([.systemSmall])
  }
}

struct MentalMathWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyMentalMath", intent: AnchorSettings.self,
      provider: SuiteTimeline<AnchorSettings>(kind: "CurrencyMentalMath")
    ) { AnchorView(entry: $0, mental: true) }
    .configurationDisplayName(Text(.Widgets.mentalTitle))
    .description(Text(.Widgets.mentalDescription))
    .supportedFamilies([.systemSmall])
  }
}
