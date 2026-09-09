import CurrencySupport
import SwiftUI
import WidgetKit

/// A presentation event, without persistence or AppIntent dependencies.
public struct WidgetCommand: Sendable {
  /// Key, selection, or preset command emitted by a shared control.
  public let command: String
  /// Canonical configuration associated with the control.
  public let spec: WidgetSpec
  /// Visible currency to activate after a widget resize.
  public let activeCurrency: String?
  /// Previously active currency hidden by the new size.
  public let hiddenCurrency: String?

  /// Creates an event without executing it or touching persistence.
  public init(
    _ command: String, spec: WidgetSpec, activeCurrency: String? = nil,
    hiddenCurrency: String? = nil
  ) {
    self.command = command; self.spec = spec
    self.activeCurrency = activeCurrency; self.hiddenCurrency = hiddenCurrency
  }
}

/// The extension supplies AppIntent buttons; the app supplies temporary preview actions.
@MainActor
public struct WidgetButtonRenderer {
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
  /// Host-owned action rendering; absent renderers produce inert labels.
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
  var body: some View {
    if let renderer { renderer.render(command, AnyView(label())) } else { label().disabled(true) }
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
