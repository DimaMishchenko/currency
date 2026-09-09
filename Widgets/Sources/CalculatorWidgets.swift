import CurrencySupport
import SwiftUI
import WidgetKit
import WidgetPresentation

struct CalculatorView: View {
  @Environment(\.widgetFamily) private var family
  let entry: SuiteEntry

  var body: some View {
    CalculatorLayout(entry: entry, family: family).modifier(WidgetInteractionContext())
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
