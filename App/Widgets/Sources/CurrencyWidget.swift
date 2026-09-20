import AppIntents
import Conversion
import ExchangeRates
import ExchangeRatesUI
import LocalCurrency
import SwiftUI
import WidgetKit
import Widgets
import WidgetsUI

struct QuickRateView: View {
  @Environment(\.widgetFamily) private var family
  let entry: CurrencyEntry
  var body: some View {
    QuickRateLayout(input: entry.input, snapshot: entry.snapshot, family: family)
  }
}

struct QuickRateWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "CurrencyQuickRate",
      provider: CurrencyTimeline(dependencies: WidgetComposition.timeline())
    ) {
      QuickRateView(entry: $0)
    }
    .configurationDisplayName(Text(.Widgets.quickRate))
    .description(Text(.Widgets.quickRateDescription))
    .supportedFamilies([.accessoryInline, .accessoryRectangular])
  }
}
