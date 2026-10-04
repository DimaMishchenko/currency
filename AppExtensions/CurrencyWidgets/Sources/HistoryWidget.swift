import SwiftUI
import WidgetKit
import WidgetsUI

struct HistoryWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyHistory", intent: HistorySettings.self,
      provider: HistoryTimeline(dependencies: WidgetComposition.history())
    ) { entry in
      HistoryWidgetContent(entry: entry)
    }
    .configurationDisplayName(Text(.Widgets.historyTitle))
    .description(Text(.Widgets.historyDescription))
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

private struct HistoryWidgetContent: View {
  @Environment(\.widgetFamily) private var family
  let entry: HistoryWidgetEntry

  var body: some View { HistoryWidgetView(entry: entry, family: family) }
}
