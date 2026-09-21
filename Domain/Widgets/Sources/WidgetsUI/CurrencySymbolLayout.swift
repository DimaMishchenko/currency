import SwiftUI
import WidgetKit
import Widgets

/// A currency logo shared by the native Lock Screen widget and its preview.
public struct CurrencySymbolLayout: View {
  let symbol: CurrencySymbol
  @Environment(\.isWidgetPreview) private var isPreview
  /// Creates a circular currency logo.
  public init(symbol: CurrencySymbol = .dollar) { self.symbol = symbol }
  /// A compact glyph centered in the system accessory background.
  public var body: some View {
    GeometryReader { geometry in
      let diameter = min(geometry.size.width, geometry.size.height)
      ZStack {
        if isPreview {
          Circle().fill(.primary.opacity(0.15))
        } else {
          AccessoryWidgetBackground()
        }
        Image(systemName: symbol.rawValue)
          .resizable().scaledToFit()
          .fontWeight(.semibold)
          .frame(width: diameter * 0.48, height: diameter * 0.48)
      }
      .frame(width: diameter, height: diameter)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(symbol.title)
  }
}
