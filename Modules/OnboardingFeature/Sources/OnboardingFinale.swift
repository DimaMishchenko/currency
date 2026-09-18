import CurrencySupport
import SwiftUI

/// Currency artwork forms an orbit that can be grabbed and spun with momentum.
struct OnboardingFinale: View {
  let moving: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 34
  @State private var elapsed: TimeInterval = 0
  @State private var started = Date.now

  @State private var spin = OnboardingOrbit()
  @State private var dragAngle: Double?
  @State private var dragTime: Date?
  @State private var dragVelocity: Double = 0

  private let currencies = ["EUR", "BTC", "USD", "XAU", "JPY", "ETH", "GBP", "XAG"]

  private var clock: TimeInterval {
    elapsed + (moving ? Date.now.timeIntervalSince(started) : 0)
  }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: !moving || reduceMotion)) { context in
      let clock = elapsed + (moving ? context.date.timeIntervalSince(started) : 0)
      let time = reduceMotion ? 3 : clock
      GeometryReader { geometry in
        let diameter = min(360, geometry.size.width - 40, geometry.size.height - 32)
        let radius = max(80, (diameter - 36) / 2)
        let orbit = spin.angle(at: clock)
        ZStack {
          ForEach(Array(currencies.enumerated()), id: \.element) { index, code in
            let progress = min(1, max(0, (time - Double(index) * 0.065) / 1.15))
            let settled = 1 - pow(1 - progress, 3)
            let angle = Double(index) * .pi / 4 - .pi / 2 + orbit - (1 - settled) * .pi * 0.7
            let breathing = reduceMotion ? 0 : sin(time * 1.1 + Double(index) * .pi / 4) * 3
            let distance = radius * (1 + (1 - settled) * 0.35) + breathing
            CurrencyIcon(code, size: 32)
              .scaleEffect(0.4 + settled * 0.6)
              .rotationEffect(.degrees(reduceMotion ? 0 : sin(time * 0.8 + Double(index)) * 4))
              .blur(radius: (1 - settled) * 5)
              .opacity(min(1, progress * 3))
              .offset(x: cos(angle) * distance, y: sin(angle) * distance)
          }
          let titleProgress = min(1, max(0, (time - 0.35) / 0.7))
          VStack(spacing: 6) {
            Text(.Onboarding.readyWelcome)
              .font(.system(size: titleSize, weight: .semibold, design: .rounded))
              .tracking(-0.6).accessibilityAddTraits(.isHeader)
            Text(.Onboarding.readyToCurrency)
              .font(AppStyle.font(.title3)).foregroundStyle(.secondary)
          }
          .lineLimit(1).minimumScaleFactor(0.5)
          .frame(width: max(150, diameter - 100))
          .opacity(titleProgress)
          .offset(y: reduceMotion ? 0 : (1 - titleProgress) * 12)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .highPriorityGesture(spinGesture(diameter: diameter))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("onboarding.ready")
    .accessibilityHint(Text(.Onboarding.spinHint))
    .accessibilityAdjustableAction { direction in
      spin.grab(at: clock)
      spin.turn(by: direction == .decrement ? -.pi / 4 : .pi / 4)
      spin.release(at: clock, velocity: 0)
    }
    .onChange(of: moving) { _, active in
      if active {
        started = .now
      } else {
        elapsed += Date.now.timeIntervalSince(started)
        spin.release(at: elapsed, velocity: 0)
        dragAngle = nil
        dragTime = nil
        dragVelocity = 0
      }
    }
  }

  private func spinGesture(diameter: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 5)
      .onChanged { value in
        let x = value.location.x - diameter / 2
        let y = value.location.y - diameter / 2
        guard hypot(x, y) > 44 else {
          dragAngle = nil
          dragVelocity = 0
          return
        }
        let angle = atan2(y, x)
        if let previous = dragAngle, let date = dragTime {
          let delta = OnboardingOrbit.shortestTurn(from: previous, to: angle)
          let interval = value.time.timeIntervalSince(date)
          spin.turn(by: delta)
          if interval > 0 {
            dragVelocity = max(-14, min(14, 0.65 * delta / interval + 0.35 * dragVelocity))
          }
        } else {
          spin.grab(at: clock)
        }
        dragAngle = angle
        dragTime = value.time
      }
      .onEnded { value in
        let fresh = dragTime.map { value.time.timeIntervalSince($0) < 0.12 } ?? false
        spin.release(at: clock, velocity: reduceMotion || !fresh ? 0 : dragVelocity)
        dragAngle = nil
        dragTime = nil
        dragVelocity = 0
      }
  }

}

/// Analytic deceleration keeps momentum independent of rendering frequency.
struct OnboardingOrbit {
  private var offset: Double = 0
  private var releasedAt: TimeInterval = 0
  private var velocity: Double = 0
  private var held = false
  private let drift = Double.pi * 2 / 32
  private let friction = 1.7

  func angle(at time: TimeInterval) -> Double {
    guard !held else { return offset }
    let duration = max(0, time - releasedAt)
    return offset + drift * duration + velocity * (1 - exp(-friction * duration)) / friction
  }

  mutating func grab(at time: TimeInterval) {
    offset = angle(at: time)
    held = true
    velocity = 0
  }

  mutating func turn(by angle: Double) { offset += angle }

  mutating func release(at time: TimeInterval, velocity: Double) {
    guard held else { return }
    releasedAt = time
    self.velocity = velocity
    held = false
  }

  static func shortestTurn(from start: Double, to end: Double) -> Double {
    atan2(sin(end - start), cos(end - start))
  }
}
