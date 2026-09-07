import CurrencySupport
import SwiftUI
import WidgetKit

struct CalculatorView: View {
  @Environment(\.widgetFamily) private var family
  let entry: SuiteEntry

  var body: some View { CalculatorLayout(entry: entry, family: family) }
}

struct CalculatorLayout: View {
  let entry: SuiteEntry
  let family: WidgetFamily

  private var codes: [String] {
    entry.input.visibleCodes(
      limit: family == .systemMedium ? 4 : 8, reservesLocal: entry.spec.synchronized)
  }

  private var displayEntry: SuiteEntry {
    var display = entry
    display.input = entry.input.displayedInput(
      limit: family == .systemMedium ? 4 : 8,
      reservesLocal: entry.spec.synchronized, snapshot: entry.snapshot)
    return display
  }

  var body: some View {
    GeometryReader { geometry in
      if entry.spec.codes.isEmpty {
        Text(.Widgets.chooseCustomCurrencies)
          .font(AppStyle.font(.callout)).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if family == .systemMedium {
        HStack(spacing: AppStyle.Space.small) {
          VStack(spacing: AppStyle.Space.xs) {
            if codes.count > 2 {
              VStack(spacing: AppStyle.Space.xs) {
                ForEach(0..<2, id: \.self) { row in
                  HStack(spacing: AppStyle.Space.xs) {
                    ForEach(
                      Array(codes.dropFirst(row * 2).prefix(2).enumerated()),
                      id: \.offset
                    ) { _, code in
                      CurrencyTile(entry: displayEntry, code: code, compact: true, stacked: true)
                    }
                    if row == 1 && codes.count == 3 {
                      Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
                        .allowsHitTesting(false)
                    }
                  }
                }
              }
            } else {
              ForEach(Array(codes.enumerated()), id: \.offset) { _, code in
                CurrencyTile(entry: displayEntry, code: code, stacked: true)
              }
            }
            WidgetFooter(entry: entry)
          }
          .frame(width: geometry.size.width * 0.46)
          WidgetKeypad(
            spec: entry.spec,
            activeCurrency: displayEntry.input.active != entry.input.active
              ? displayEntry.input.active : nil,
            hiddenCurrency: displayEntry.input.active != entry.input.active
              ? entry.input.active : nil
          )
          .disabled(
            !codes.contains(displayEntry.input.active)
              || displayEntry.input.active == WidgetSelection.localID)
        }
      } else {
        VStack(spacing: AppStyle.Space.small) {
          let rows = max(1, (codes.count + 1) / 2)
          VStack(spacing: AppStyle.Space.xs) {
            ForEach(0..<rows, id: \.self) { row in
              HStack(spacing: AppStyle.Space.xs) {
                ForEach(
                  Array(codes.dropFirst(row * 2).prefix(2).enumerated()), id: \.offset
                ) { _, code in
                  CurrencyTile(
                    entry: displayEntry, code: code, compact: rows == 4, stacked: rows == 1,
                    showsCode: rows != 4)
                }
                if row * 2 + 1 >= codes.count {
                  Color.clear.frame(maxWidth: .infinity)
                    .accessibilityHidden(true).allowsHitTesting(false)
                }
              }
            }
          }
          .frame(height: max(56, geometry.size.height * (rows == 1 ? 0.26 : 0.43)))
          WidgetKeypad(
            spec: entry.spec,
            activeCurrency: displayEntry.input.active != entry.input.active
              ? displayEntry.input.active : nil,
            hiddenCurrency: displayEntry.input.active != entry.input.active
              ? entry.input.active : nil
          )
          .disabled(
            !codes.contains(displayEntry.input.active)
              || displayEntry.input.active == WidgetSelection.localID)
          WidgetFooter(entry: entry)
        }
      }
    }
    .animation(nil, value: entry.input)
    .modifier(WidgetSurface())
  }

}

struct MultiCurrencyWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyConverter", intent: MultiSettings.self,
      provider: SuiteTimeline<MultiSettings>(kind: "CurrencyConverter")
    ) { CalculatorView(entry: $0) }
    .configurationDisplayName(Text(.Widgets.multiTitle))
    .description(
      .Widgets.multiDescription
    )
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}
