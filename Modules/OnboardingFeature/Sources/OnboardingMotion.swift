import CurrencySupport
import SwiftUI

/// One fixed optical box; the supported symbol replacement has a standard fallback.
struct CurrencySymbolLoader: View {
  let moving: Bool
  @State private var index = 1
  private let symbols = ["dollarsign", "eurosign", "sterlingsign", "yensign"]
  var body: some View {
    Image(systemName: moving ? symbols[index] : "eurosign")
      .font(.system(size: 26, weight: .medium, design: .rounded))
      .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
      .frame(width: 40, height: 40)
      .accessibilityHidden(true)
      .task(id: moving) {
        guard moving else { return }
        while !Task.isCancelled {
          do { try await Task.sleep(for: .milliseconds(720)) } catch { return }
          withAnimation(.easeInOut(duration: 0.28)) { index = (index + 1) % symbols.count }
        }
      }
  }
}

/// Deterministic positions and independent slow periods keep the field quiet and asymmetric.
struct CurrencyDepthField: View {
  let moving: Bool
  let sparse: Bool
  let appeared: Bool
  @Environment(\.colorScheme) private var colorScheme
  @State private var elapsed: TimeInterval = 0
  @State private var started = Date.now
  private struct Asset {
    let code: String
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
    let blur: CGFloat
    let period: Double
    let phase: Double
  }
  private let assets: [Asset] = [
    .init(code: "EUR", x: 0.22, y: 0.16, size: 26, opacity: 0.44, blur: 0.4, period: 11, phase: 0),
    .init(code: "CNY", x: 0.68, y: 0.10, size: 16, opacity: 0.23, blur: 1.4, period: 13, phase: 2),
    .init(code: "USD", x: 0.56, y: 0.25, size: 23, opacity: 0.34, blur: 0.6, period: 9, phase: 4),
    .init(code: "BTC", x: 0.88, y: 0.26, size: 28, opacity: 0.42, blur: 0.8, period: 12, phase: 1),
    .init(code: "BRL", x: 0.09, y: 0.39, size: 27, opacity: 0.43, blur: 0.3, period: 10, phase: 3),
    .init(code: "CHF", x: 0.87, y: 0.52, size: 26, opacity: 0.34, blur: 0.7, period: 8, phase: 5),
    .init(code: "MXN", x: 0.13, y: 0.64, size: 19, opacity: 0.26, blur: 1.1, period: 14, phase: 2),
    .init(code: "SOL", x: 0.80, y: 0.71, size: 26, opacity: 0.20, blur: 1.2, period: 11, phase: 4),
    .init(code: "GBP", x: 0.36, y: 0.81, size: 23, opacity: 0.35, blur: 0.6, period: 9, phase: 1),
    .init(code: "INR", x: 0.66, y: 0.91, size: 16, opacity: 0.22, blur: 1.3, period: 13, phase: 3)
  ]
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: !moving)) { context in
      let time = elapsed + (moving ? context.date.timeIntervalSince(started) : 0)
      GeometryReader { geometry in
        ForEach(assets.indices, id: \.self) { index in
          let asset = assets[index]
          let phase = time * .pi * 2 / asset.period + asset.phase
          CurrencyIcon(asset.code, size: asset.size)
            .blur(radius: asset.blur)
            .opacity(opacity(for: index))
            .rotationEffect(.degrees(sin(phase * 0.7) * (sparse ? 3 : 7)))
            .scaleEffect(1 + sin(phase * 0.6) * (sparse ? 0.015 : 0.035))
            .offset(x: sin(phase) * (sparse ? 3 : 7), y: cos(phase * 0.8) * (sparse ? 4 : 9))
            .position(x: asset.x * geometry.size.width, y: asset.y * geometry.size.height)
        }
      }
    }
    .allowsHitTesting(false).accessibilityHidden(true)
    .onChange(of: moving) { _, active in
      if active { started = .now } else { elapsed += Date.now.timeIntervalSince(started) }
    }
  }

  private func opacity(for index: Int) -> Double {
    guard appeared else { return 0 }
    if sparse {
      return [0, 1, 3, 4].contains(index) ? (colorScheme == .dark ? 0.16 : 0.10) : 0
    }
    return assets[index].opacity * (colorScheme == .dark ? 1.15 : 1)
  }
}

/// Small independently staged entrances keep final typography stable throughout navigation.
struct OnboardingReveal: AnimatableModifier {
  nonisolated var progress: CGFloat
  var delay: CGFloat = 0
  var offset: CGFloat = 12
  var scale: CGFloat = 1
  var reduced = false
  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }
  func body(content: Content) -> some View {
    let value = min(1, max(0, (progress - (reduced ? 0 : delay)) / (1 - (reduced ? 0 : delay))))
    content.opacity(value)
      .offset(y: reduced ? 0 : offset * (1 - value))
      .scaleEffect(reduced ? 1 : scale + (1 - scale) * value)
  }
}

/// Outgoing scenes recede as a composition; labels never morph between unrelated layouts.
struct OnboardingDeparture: AnimatableModifier {
  nonisolated var progress: CGFloat
  var forward: Bool
  var reduced: Bool
  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }
  func body(content: Content) -> some View {
    content.opacity(1 - progress)
      .offset(y: reduced ? 0 : (forward ? -8 : 6) * progress)
      .scaleEffect(reduced ? 1 : 1 - 0.025 * progress)
  }
}
