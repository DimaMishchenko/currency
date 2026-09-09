import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit

/// The inline or rectangular Lock Screen conversion layout.
public struct QuickRateLayout: View {
  @Environment(\.locale) private var locale
  let input: ConverterState
  let snapshot: RateSnapshot
  let family: WidgetFamily
  /// Creates a Lock Screen layout from the app conversion and supplied rates.
  public init(input: ConverterState, snapshot: RateSnapshot, family: WidgetFamily) {
    self.input = input; self.snapshot = snapshot; self.family = family
  }
  private var target: String { input.destinations.first ?? input.source }

  private var amount: String {
    CurrencyDisplay.format(
      snapshot.convert(input.decimal, from: input.source, to: target),
      code: target, locale: locale)
  }

  /// The source amount and its converted reference value.
  public var body: some View {
    Group {
      if family == .accessoryInline {
        Text(

          .WidgetPresentation.inlineConversion(
            CurrencyDisplay.inputAmount(input.amount, locale: locale),
            CurrencyDisplay.flag(input.source) + " " + input.source,
            amount, CurrencyDisplay.flag(target) + " " + target))
      } else {
        VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
          HStack(spacing: AppStyle.Space.xs) {
            CurrencyIcon(input.source, size: 16)
            Text(
              "\(CurrencyDisplay.inputAmount(input.amount, locale: locale)) \(input.source)"
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
    .modifier(WidgetContainerBackground(clear: true))
    .widgetURL(URL(string: "currency://convert"))
  }
}
