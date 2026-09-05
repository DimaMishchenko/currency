import CurrencySupport
import SwiftUI
import WidgetKit

struct CalculatorView: View {
  @Environment(\.widgetFamily) private var family
  let entry: SuiteEntry
  var pair = false

  var body: some View { CalculatorLayout(entry: entry, pair: pair, family: family) }
}

struct CalculatorLayout: View {
  let entry: SuiteEntry
  var pair = false
  let family: WidgetFamily

  private var codes: [String] {
    pair ? entry.spec.codes : entry.input.visibleCodes(limit: family == .systemMedium ? 4 : 8)
  }

  var body: some View {
    GeometryReader { geometry in
      if family == .systemMedium {
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
                      CurrencyTile(entry: entry, code: code, compact: true, stacked: true)
                    }
                    if row == 1 && codes.count == 3 {
                      Color.clear.frame(maxWidth: .infinity)
                    }
                  }
                }
              }
            } else {
              ForEach(Array(codes.enumerated()), id: \.offset) { _, code in
                CurrencyTile(entry: entry, code: code, stacked: true)
              }
            }
            WidgetFooter(entry: entry)
          }
          .frame(width: geometry.size.width * 0.46)
          WidgetKeypad(spec: entry.spec)
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
                    entry: entry, code: code, compact: rows == 4, stacked: rows == 1,
                    showsCode: rows != 4)
                }
              }
            }
          }
          .frame(height: max(56, geometry.size.height * (pair || rows == 1 ? 0.26 : 0.43)))
          WidgetKeypad(spec: entry.spec)
          WidgetFooter(entry: entry)
        }
      }
    }
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

struct PairCalculatorWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyPairCalculator", intent: PairSettings.self,
      provider: SuiteTimeline<PairSettings>(kind: "CurrencyPairCalculator")
    ) { CalculatorView(entry: $0, pair: true) }
    .configurationDisplayName(Text(.Widgets.pairTitle))
    .description(Text(.Widgets.pairDescription))
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}
