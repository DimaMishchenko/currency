import CurrencySupport
import SwiftUI
import WidgetKit
import WidgetPresentation

struct CashWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyCash", intent: CashSettings.self,
      provider: SuiteTimeline<CashSettings>(kind: "CurrencyCash")
    ) { CashView(entry: $0).modifier(WidgetInteractionContext()) }
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
    ) { AnchorView(entry: $0).modifier(WidgetInteractionContext()) }
    .configurationDisplayName(Text(.Widgets.pocketTitle))
    .description(Text(.Widgets.pocketDescription))
    .supportedFamilies([.systemSmall])
    .containerBackgroundRemovable(false)
  }
}

struct MentalMathWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyMentalMath", intent: AnchorSettings.self,
      provider: SuiteTimeline<AnchorSettings>(kind: "CurrencyMentalMath")
    ) { AnchorView(entry: $0, mental: true).modifier(WidgetInteractionContext()) }
    .configurationDisplayName(Text(.Widgets.mentalTitle))
    .description(Text(.Widgets.mentalDescription))
    .supportedFamilies([.systemSmall])
    .containerBackgroundRemovable(false)
  }
}
