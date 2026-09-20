import Conversion
import ExchangeRatesUI
import LocalCurrency
import SwiftUI
import WidgetKit
import Widgets
import WidgetsUI

struct BoardView: View {
  @Environment(\.widgetFamily) private var family
  let entry: SuiteEntry

  var body: some View {
    BoardLayout(family: family, entry: entry).modifier(WidgetInteractionContext())
  }
}

struct CurrencyBoardWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyBoard", intent: BoardSettings.self,
      provider: SuiteTimeline<BoardSettings>(
        kind: "CurrencyBoard", dependencies: WidgetComposition.timeline())
    ) { BoardView(entry: $0) }
    .configurationDisplayName(Text(.Widgets.board))
    .description(Text(.Widgets.newBoardDescription))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
