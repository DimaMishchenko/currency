import CurrencySupport
import SwiftUI

struct WidgetSurface: ViewModifier {
  func body(content: Content) -> some View {
    content
      // Fixed widget bounds cannot accommodate unbounded text growth; VoiceOver retains full values.
      .dynamicTypeSize(...DynamicTypeSize.large)
      .font(AppStyle.font(.caption))
      .tint(Color(uiColor: .label))
      .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
      .widgetURL(URL(string: "currency://convert"))
  }
}

struct WidgetFooter: View {
  let entry: SuiteEntry

  var body: some View {
    if entry.spec.usesLocation && !entry.spec.locationAvailable {
      Label(.Widgets.fallback, systemImage: "location.slash")
        .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
        .lineLimit(1).minimumScaleFactor(0.7)
    }
  }
}

struct WidgetKeypad: View {
  @Environment(\.locale) private var locale
  let spec: WidgetSpec

  var body: some View {
    GeometryReader { geometry in
      let cell = max(0, (geometry.size.width - AppStyle.Space.xs * 3) / 4)
      VStack(spacing: AppStyle.Space.xs) {
        ForEach(
          [["7", "8", "9", "⌫"], ["4", "5", "6", "AC"], ["1", "2", "3", "000"], [".", "0", "00"]],
          id: \.self
        ) { row in
          HStack(spacing: AppStyle.Space.xs) {
            ForEach(row, id: \.self) { key in
              Button(intent: WidgetAction(key, spec: spec)) {
                Group {
                  if key == "⌫" {
                    Image(systemName: "delete.left")
                  } else {
                    Text(key == "AC" ? "C" : CurrencyDisplay.inputAmount(key, locale: locale))
                  }
                }
                .font(
                  AppStyle.font(
                    key.count > 1 && key != "AC" ? .subheadline : .title3, weight: .medium)
                )
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: key == "0" ? cell * 2 + AppStyle.Space.xs : cell)
                .frame(maxHeight: .infinity)
                .background(
                  .primary.opacity(AppStyle.Widget.keyFill),
                  in: .rect(cornerRadius: AppStyle.Widget.keyRadius)
                )
                .overlay {
                  RoundedRectangle(cornerRadius: AppStyle.Widget.keyRadius)
                    .strokeBorder(.primary.opacity(AppStyle.Widget.keyBorder), lineWidth: 1)
                }
                .contentShape(.rect)
              }
              .accessibilityLabel(
                key == "AC"
                  ? Text(.Widgets.clear)
                  : key == "⌫"
                    ? Text(.Widgets.delete)
                    : key == "." ? Text(.Widgets.decimalSeparator) : Text(verbatim: key))
            }
          }
        }
      }
      .buttonStyle(.plain)
    }
  }
}

struct CurrencyTile: View {
  @Environment(\.locale) private var locale
  let entry: SuiteEntry
  let code: String
  var compact = false
  var stacked = false
  var showsCode = true

  private var selected: Bool { code == entry.input.active }

  var body: some View {
    Button(intent: WidgetAction("select:" + code, spec: entry.spec)) {
      Group {
        if stacked {
          VStack(alignment: .trailing, spacing: AppStyle.Space.xs) {
            HStack(spacing: AppStyle.Space.xxs) {
              CurrencyIcon(code, size: compact ? 16 : 22)
              Spacer(minLength: 0)
              currencyCode
            }
            amount.font(AppStyle.font(compact ? .title2 : .title, weight: .medium))
              .frame(maxWidth: .infinity, alignment: .trailing)
          }
          .padding(.vertical, AppStyle.Space.xs)
        } else {
          HStack(spacing: AppStyle.Space.xs) {
            CurrencyIcon(code, size: compact ? 16 : 22)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
              if showsCode { currencyCode }
              amount.font(AppStyle.font(.title2, weight: .medium))
            }
          }
        }
      }
      .padding(.horizontal, compact ? AppStyle.Space.xs : AppStyle.Space.small)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        .primary.opacity(selected ? AppStyle.Widget.selectedFill : AppStyle.Widget.tileFill),
        in: .rect(cornerRadius: compact ? AppStyle.Widget.keyRadius : AppStyle.Widget.tileRadius)
      )
      .overlay {
        RoundedRectangle(
          cornerRadius: compact ? AppStyle.Widget.keyRadius : AppStyle.Widget.tileRadius
        )
        .strokeBorder(
          .primary.opacity(selected ? AppStyle.Widget.selectedBorder : 0), lineWidth: 1.2)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(CurrencyDisplay.name(code)), \(code)")
    .accessibilityValue(
      selected
        ? entry.input.amount
        : CurrencyDisplay.format(
          entry.snapshot.convert(entry.input.decimal, from: entry.input.active, to: code),
          code: code, locale: locale)
    )
    .accessibilityHint(.Widgets.selectCurrencyHint)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var currencyCode: some View {
    Text(verbatim: code).font(AppStyle.font(.caption2, weight: .medium))
  }

  private var amount: some View {
    Text(
      selected
        ? (entry.input.replacesOnDigit
          ? CurrencyDisplay.format(entry.input.decimal, code: code, locale: locale)
          : CurrencyDisplay.inputAmount(entry.input.amount, locale: locale))
        : CurrencyDisplay.format(
          entry.snapshot.convert(entry.input.decimal, from: entry.input.active, to: code),
          code: code, locale: locale)
    )
    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
    .contentTransition(.numericText())
    .invalidatableContent()
  }
}
