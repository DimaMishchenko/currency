import SwiftUI
import WidgetsUI

struct WidgetInteractionContext: ViewModifier {
  func body(content: Content) -> some View {
    content.environment(
      \.widgetButtonRenderer,
      WidgetButtonRenderer { command, label in
        AnyView(Button(intent: WidgetAction(command)) { label })
      })
  }
}
