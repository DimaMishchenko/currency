import Conversion
import DesignSystem
import ExchangeRatesUI
import LocalCurrency
import SwiftUI
import WidgetKit
import Widgets

/// The extension supplies AppIntent buttons; the app supplies temporary preview actions.
@MainActor
public struct WidgetButtonRenderer {
  /// Explicitly renders disabled labels for placeholders and noninteractive hosts.
  public static var inert: Self { Self { _, label in AnyView(label.disabled(true)) } }
  let render: (WidgetCommand, AnyView) -> AnyView
  /// Supplies the host-specific button implementation for shared labels.
  public init(_ render: @escaping (WidgetCommand, AnyView) -> AnyView) { self.render = render }
}

private struct WidgetButtonRendererKey: EnvironmentKey {
  static let defaultValue: WidgetButtonRenderer? = nil
}
private struct WidgetPreviewKey: EnvironmentKey {
  static let defaultValue = false
}
public extension EnvironmentValues {
  /// Required host-owned action rendering.
  var widgetButtonRenderer: WidgetButtonRenderer? {
    get { self[WidgetButtonRendererKey.self] }
    set { self[WidgetButtonRendererKey.self] = newValue }
  }
  /// Omits WidgetKit container backgrounds when the app hosts a preview.
  var isWidgetPreview: Bool {
    get { self[WidgetPreviewKey.self] }
    set { self[WidgetPreviewKey.self] = newValue }
  }
}

struct WidgetPresentationButton<Label: View>: View {
  @Environment(\.widgetButtonRenderer) private var renderer
  let command: WidgetCommand
  @ViewBuilder let label: () -> Label
  private var rendererRequired: WidgetButtonRenderer {
    guard let renderer else { preconditionFailure("WidgetsUI requires a widgetButtonRenderer") }
    return renderer
  }
  var body: some View {
    rendererRequired.render(command, AnyView(label()))
  }
}

struct WidgetContainerBackground: ViewModifier {
  @Environment(\.isWidgetPreview) private var preview
  var clear = false
  func body(content: Content) -> some View {
    if preview {
      content
    } else {
      content.containerBackground(for: .widget) {
        if clear { Color.clear } else { Color(uiColor: .systemBackground) }
      }
    }
  }
}
