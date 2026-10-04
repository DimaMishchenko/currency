import AppIntents
import Foundation
import SwiftUI
import WidgetKit

@main
struct CurrencyWatchWidgets: WidgetBundle {
  var body: some Widget {
    WatchPairWidget(style: .pocket)
    WatchBoardWidget(style: .board)
    WatchHistoryWidget()
    WatchPairWidget(style: .mental)
    WatchCashWidget()
    WatchCurrencyIconWidget()
    WatchBoardWidget(style: .favorites)
    OpenCurrencyWatchControl()
  }
}

struct WatchPairWidget: Widget {
  let style: WatchWidgetStyle
  init() { style = .pocket }
  init(style: WatchWidgetStyle) { self.style = style }
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: style.kind, intent: WatchPairSettings.self,
      provider: WatchPairTimeline(style: style)
    ) {
      WatchRateView(entry: $0)
    }
    .configurationDisplayName(Text(title))
    .description(Text(description))
    .supportedFamilies([
      .accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner
    ])
  }
  private var title: LocalizedStringResource {
    switch style {
    case .mental: .WatchWidgets.mentalTitle
    case .cash: .WatchWidgets.cashTitle
    default: .WatchWidgets.pocketTitle
    }
  }
  private var description: LocalizedStringResource {
    switch style {
    case .mental: .WatchWidgets.mentalDescription
    case .cash: .WatchWidgets.cashDescription
    default: .WatchWidgets.pocketDescription
    }
  }
}

struct WatchCashWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WatchWidgetStyle.cash.kind, intent: WatchCashSettings.self,
      provider: WatchCashTimeline()
    ) { WatchRateView(entry: $0) }
    .configurationDisplayName(Text(.WatchWidgets.cashTitle))
    .description(Text(.WatchWidgets.cashDescription))
    .supportedFamilies([
      .accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner
    ])
  }
}

struct WatchBoardWidget: Widget {
  let style: WatchWidgetStyle
  init() { style = .board }
  init(style: WatchWidgetStyle) { self.style = style }
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: style.kind, intent: WatchBoardSettings.self,
      provider: WatchBoardTimeline(style: style)
    ) {
      WatchBoardView(entry: $0)
    }
    .configurationDisplayName(
      Text(style == .favorites ? .WatchWidgets.favoritesTitle : .WatchWidgets.boardTitle)
    )
    .description(
      Text(
        style == .favorites ? .WatchWidgets.favoritesDescription : .WatchWidgets.boardDescription)
    )
    .supportedFamilies(
      style == .favorites
        ? [.accessoryRectangular]
        : [.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
  }
}

struct WatchHistoryWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyWatch-history", intent: WatchHistorySettings.self,
      provider: WatchHistoryTimeline()
    ) { WatchHistoryView(entry: $0) }
    .configurationDisplayName(Text(.WatchWidgets.historyTitle))
    .description(Text(.WatchWidgets.historyDescription))
    .supportedFamilies([
      .accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner
    ])
  }
}

struct WatchCurrencyIconWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "CurrencyWatch-icon", intent: WatchIconSettings.self,
      provider: WatchIconTimeline()
    ) { WatchIconView(entry: $0) }
    .configurationDisplayName(Text(.WatchWidgets.iconTitle))
    .description(Text(.WatchWidgets.iconDescription))
    .supportedFamilies([
      .accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner
    ])
  }
}

struct OpenCurrencyWatchControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "CurrencyWatch-open") {
      ControlWidgetButton(action: OpenWatchCurrencyIntent()) {
        Label {
          Text(.WatchWidgets.openCurrency)
        } icon: {
          Image(systemName: "arrow.left.arrow.right")
        }
      }
    }
    .displayName(.WatchWidgets.openCurrency)
    .description(.WatchWidgets.openDescription)
  }
}

#Preview(as: .accessoryRectangular) {
  WatchPairWidget(style: .pocket)
} timeline: {
  WatchWidgetPreview.entry(style: .pocket)
}

#Preview(as: .accessoryRectangular) {
  WatchHistoryWidget()
} timeline: {
  WatchWidgetPreview.history()
}
