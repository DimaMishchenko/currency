import SwiftUI
import WidgetsUI

/// AppIntent construction stays in the extension so installed widgets retain their intent identities.
struct WidgetInteractionContext: ViewModifier {
  func body(content: Content) -> some View {
    content.environment(
      \.widgetButtonRenderer,
      WidgetButtonRenderer { command, label in
        AnyView(Button(intent: WidgetAction(command)) { label })
      })
  }
}
