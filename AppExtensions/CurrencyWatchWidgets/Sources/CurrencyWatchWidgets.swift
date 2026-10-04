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
    .configurationDisplayName(String(localized: title))
    .description(String(localized: description))
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
    .configurationDisplayName(String(localized: .WatchWidgets.cashTitle))
    .description(String(localized: .WatchWidgets.cashDescription))
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
      String(
        localized: style == .favorites ? .WatchWidgets.favoritesTitle : .WatchWidgets.boardTitle)
    )
    .description(
      String(
        localized: style == .favorites
          ? .WatchWidgets.favoritesDescription : .WatchWidgets.boardDescription)
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
    .configurationDisplayName(String(localized: .WatchWidgets.historyTitle))
    .description(String(localized: .WatchWidgets.historyDescription))
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
          Image(systemName: "dollarsign")
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
