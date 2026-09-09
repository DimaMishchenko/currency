import CurrencySupport
import SwiftUI
import WidgetKit
import WidgetPresentation

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
      provider: SuiteTimeline<BoardSettings>(kind: "CurrencyBoard")
    ) { BoardView(entry: $0) }
    .configurationDisplayName(Text(.Widgets.board))
    .description(Text(.Widgets.newBoardDescription))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
