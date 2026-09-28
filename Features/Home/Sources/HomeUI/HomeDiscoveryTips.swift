import SwiftUI
import TipKit

struct RateHistoryTip: Tip {
  var title: Text { Text(.Converter.historyTipTitle) }
  var message: Text? { Text(.Converter.historyTipMessage) }
}

struct ExploreWidgetsTip: Tip {
  var title: Text { Text(.Converter.widgetsTipTitle) }
  var message: Text? { Text(.Converter.widgetsTipMessage) }
}

@MainActor
struct HomeDiscoveryPopover<Content: Tip>: View {
  let tip: Content
  let presented: () -> Void
  let dismissed: () -> Void

  var body: some View {
    TipView(tip)
      .onAppear(perform: presented)
      .task {
        for await status in tip.statusUpdates {
          if case .invalidated = status {
            dismissed()
            return
          }
        }
      }
      .presentationCompactAdaptation(.popover)
      .presentationBackgroundInteraction(.enabled)
  }
}
