import AppIntents
import SwiftUI
import WidgetKit
import Widgets
import WidgetsUI

struct CurrencyIconEntry: TimelineEntry {
  let date: Date
  let symbol: CurrencySymbol
}

struct CurrencyIconTimeline: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> CurrencyIconEntry { .init(date: .now, symbol: .dollar) }
  func snapshot(
    for configuration: CurrencyIconSettings, in context: Context
  ) async -> CurrencyIconEntry {
    .init(date: .now, symbol: configuration.symbol.symbol)
  }
  func timeline(
    for configuration: CurrencyIconSettings, in context: Context
  ) async -> Timeline<CurrencyIconEntry> {
    Timeline(entries: [await snapshot(for: configuration, in: context)], policy: .never)
  }
}

struct CurrencyIconWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyIcon", intent: CurrencyIconSettings.self, provider: CurrencyIconTimeline()
    ) { entry in
      CurrencySymbolLayout(symbol: entry.symbol)
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "currency://convert"))
    }
    .configurationDisplayName("Currency Icon")
    .description("A currency symbol for your Lock Screen. Tap to open Currency.")
    .supportedFamilies([.accessoryCircular])
  }
}
