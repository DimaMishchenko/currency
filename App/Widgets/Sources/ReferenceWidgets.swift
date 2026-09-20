import Conversion
import ExchangeRatesUI
import LocalCurrency
import SwiftUI
import WidgetKit
import Widgets
import WidgetsUI

struct CashWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyCash", intent: CashSettings.self,
      provider: SuiteTimeline<CashSettings>(
        kind: "CurrencyCash", dependencies: WidgetComposition.timeline())
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
      provider: SuiteTimeline<AnchorSettings>(
        kind: "CurrencyPocketRate", dependencies: WidgetComposition.timeline())
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
      provider: SuiteTimeline<AnchorSettings>(
        kind: "CurrencyMentalMath", dependencies: WidgetComposition.timeline())
    ) { AnchorView(entry: $0, mental: true).modifier(WidgetInteractionContext()) }
    .configurationDisplayName(Text(.Widgets.mentalTitle))
    .description(Text(.Widgets.mentalDescription))
    .supportedFamilies([.systemSmall])
    .containerBackgroundRemovable(false)
  }
}
