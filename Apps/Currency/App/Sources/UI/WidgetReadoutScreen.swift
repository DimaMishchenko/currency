import CurrencyApplication
import ExchangeRates
import ExchangeRatesUI
import SwiftUI
import Widgets

struct WidgetReadoutScreen: View {
  let readout: CurrencyScene.WidgetReadout
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale

  var body: some View {
    NavigationStack {
      ScrollView {
        if let context = readout.context, let input = context.renderedInput {
          LazyVStack(alignment: .leading, spacing: 24) {
            if context.renderedKind == "CurrencyMentalMath" {
              mentalRule(input: input, snapshot: context.snapshot)
            }
            ForEach(input.codes, id: \.self) { selection in
              row(selection, input: input, snapshot: context.snapshot)
            }
          }
          .padding()
        } else {
          ContentUnavailableView {
            Label {
              Text("Widget amounts unavailable", tableName: "WidgetReadout")
            } icon: {
              Image(systemName: "widget.small")
            }
          } description: {
            Text(
              "Open the widget again to capture its current amounts.", tableName: "WidgetReadout")
          }
        }
      }
      .navigationTitle(Text("Widget amounts", tableName: "WidgetReadout"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text("Done", tableName: "WidgetReadout")
          }
          .accessibilityIdentifier("widget.readout.done")
        }
      }
      .accessibilityIdentifier("widget.readout")
    }
    .fontDesign(.rounded)
  }

  @ViewBuilder
  private func mentalRule(input: WidgetInput, snapshot: RateSnapshot) -> some View {
    let base = WidgetSelection.currency(input.codes.first ?? "EUR")
    let target = WidgetSelection.currency(input.codes.last ?? "USD")
    if let rate = snapshot.convert(1, from: base, to: target, metalUnit: input.metalUnit),
      let rule = WidgetMath.rule(rate: rate)
    {
      VStack(alignment: .leading, spacing: 8) {
        Text(verbatim: base + " → " + target).font(.headline)
        if rule.divide {
          Text("Divide by", tableName: "WidgetReadout").font(.title2)
        } else {
          Text("Multiply by", tableName: "WidgetReadout").font(.title2)
        }
        Text(verbatim: CurrencyDisplay.format(rule.factor, code: "BTC", locale: locale))
          .font(.largeTitle).monospacedDigit()
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("widget.readout.mentalRule")
    }
  }

  private func row(_ selection: String, input: WidgetInput, snapshot: RateSnapshot) -> some View {
    let code = WidgetSelection.currency(selection)
    let isLocal = WidgetSelection.isLocal(selection)
    let isMetal = CurrencyCode(rawValue: code)?.isMetal == true
    return VStack(alignment: .leading, spacing: 8) {
      if selection == WidgetSelection.localID {
        Text("Local currency", tableName: "WidgetReadout")
          .font(.headline)
        Text("Unavailable", tableName: "WidgetReadout")
          .font(.title)
      } else {
        Text(CurrencyDisplay.name(code, locale: locale))
          .font(.headline)
        if isLocal {
          Text("Local currency", tableName: "WidgetReadout")
            .font(.subheadline)
        }
        Text(verbatim: code + (isMetal ? " · " + input.metalUnit.symbol : ""))
          .font(.subheadline)
        Text(verbatim: amount(selection, input: input, snapshot: snapshot))
          .font(.title).monospacedDigit()
          .textSelection(.enabled)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("widget.readout.\(selection)")
  }

  private func amount(_ selection: String, input: WidgetInput, snapshot: RateSnapshot) -> String {
    if selection == input.active && !input.replacesOnDigit {
      return CurrencyDisplay.inputAmount(input.amount, locale: locale)
    }
    let value =
      selection == input.active
      ? input.decimal
      : snapshot.convert(
        input.decimal, from: WidgetSelection.currency(input.active),
        to: WidgetSelection.currency(selection), metalUnit: input.metalUnit)
    return CurrencyDisplay.format(
      value, code: WidgetSelection.currency(selection), locale: locale, metalUnit: input.metalUnit)
  }
}
