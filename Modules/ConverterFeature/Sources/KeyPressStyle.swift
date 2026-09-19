import SwiftUI

struct KeyPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(Color.primary)
      .background(
        Color.primary.opacity(configuration.isPressed ? 0.07 : 0),
        in: RoundedRectangle(cornerRadius: 16)
      )
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
  }
}
