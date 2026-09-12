import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit

/// Establishes Home Screen placement before introducing individual widget kinds.
public struct OnboardingHomeScreen: View {
  private let snapshot: RateSnapshot
  private let input: ConverterState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var entrance = HomeScreenEntranceClock()
  private static let appRows = [
    ["calendar", "photo", "map", "book.closed"],
    ["clock", "camera", "cloud.sun", "gearshape"],
    ["phone", "safari", "bubble.left.and.bubble.right", "music.note"]
  ]

  /// Uses the same personalized calculator presentation as the widget extension.
  public init(snapshot: RateSnapshot, input: ConverterState) {
    self.snapshot = snapshot
    self.input = input
  }

  /// An illustrative Home Screen with one interactive production widget and subdued apps.
  public var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 60, paused: !entrance.isRunning)) { timeline in
      GeometryReader { geometry in
        let scale = min((geometry.size.width - 64) / 250, (geometry.size.height - 24) / 472, 1)
        let time =
          reduceMotion ? HomeScreenEntranceClock.duration : entrance.time(at: timeline.date)
        let arrival = reveal(time, start: 0, duration: 0.55)
        phone(time: time)
          .scaleEffect(scale * (0.965 + 0.035 * arrival))
          .opacity(reveal(time, start: 0, duration: 0.20))
          .offset(y: 10 * (1 - arrival))
          .frame(width: geometry.size.width, height: geometry.size.height)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(.WidgetOnboarding.homeScreenPreview))
    .accessibilityIdentifier("onboarding.homeScreen")
    .onAppear { updatePlayback() }
    .onChange(of: scenePhase) { _, _ in updatePlayback() }
    .onChange(of: reduceMotion) { _, _ in updatePlayback() }
    .onDisappear { entrance.setActive(false, reduceMotion: reduceMotion, now: .now) }
    .task(id: entrance.startedAt) {
      guard let started = entrance.startedAt else { return }
      do {
        try await Task.sleep(for: .seconds(HomeScreenEntranceClock.duration - entrance.elapsed))
        guard entrance.startedAt == started else { return }
        entrance.finish()
      } catch { return }
    }
  }

  private func phone(time: TimeInterval) -> some View {
    VStack(spacing: 16) {
      Capsule().fill(.black.opacity(0.8)).frame(width: 62, height: 15)
        .padding(.top, 12).accessibilityHidden(true)
      VStack(spacing: 5) {
        WidgetPreview(
          kind: .calculator, family: .systemMedium, interactive: true,
          codes: [input.source] + input.destinations,
          amount: input.amount, snapshot: snapshot, converterInput: input
        )
        .scaleEffect(218 / WidgetFamily.systemMedium.previewSize.width)
        .frame(
          width: 218,
          height: 218 * WidgetFamily.systemMedium.previewSize.height
            / WidgetFamily.systemMedium.previewSize.width
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .accessibilityHint(Text(.WidgetOnboarding.previewCalculatorHint))
        Text(.WidgetOnboarding.currencyAppName)
          .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      .opacity(reveal(time, start: 0.10, duration: 0.38))
      .offset(y: 6 * (1 - reveal(time, start: 0.10, duration: 0.45)))
      VStack(spacing: 20) {
        iconRow(Self.appRows[0], offset: 0, time: time)
        iconRow(Self.appRows[1], offset: 4, time: time)
      }
      Spacer(minLength: 8)
      HStack(spacing: 5) {
        Circle().fill(.primary.opacity(0.4))
        Circle().fill(.primary.opacity(0.15))
      }
      .frame(width: 13, height: 4)
      .opacity(reveal(time, start: 0.35, duration: 0.3))
      .accessibilityHidden(true)
      iconRow(Self.appRows[2], offset: 8, time: time)
        .padding(.vertical, 12)
        .background {
          RoundedRectangle(cornerRadius: 24)
            .fill(.background.opacity(reduceTransparency ? 1 : 0.55))
            .opacity(reveal(time, start: 0.3, duration: 0.4))
        }
        .padding(.horizontal, 10)
      Capsule().fill(.primary.opacity(0.5)).frame(width: 76, height: 3)
        .padding(.bottom, 8).accessibilityHidden(true)
    }
    .frame(width: 250, height: 472)
    .background {
      RoundedRectangle(cornerRadius: 38)
        .fill(Color(uiColor: .secondarySystemBackground))
        .overlay {
          if !reduceTransparency {
            RoundedRectangle(cornerRadius: 38)
              .fill(
                LinearGradient(
                  colors: [.cyan.opacity(0.1), .clear, .blue.opacity(0.08)],
                  startPoint: .topLeading, endPoint: .bottomTrailing)
              )
              .opacity(reveal(time, start: 0.04, duration: 0.48))
          }
        }
    }
    .clipShape(.rect(cornerRadius: 38))
    .overlay {
      RoundedRectangle(cornerRadius: 38)
        .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.22 : 0.13), lineWidth: 3)
    }
    .shadow(color: .black.opacity(0.07), radius: 14, y: 8)
  }

  private func iconRow(_ symbols: [String], offset: Int, time: TimeInterval) -> some View {
    HStack(spacing: 14) {
      ForEach(symbols.indices, id: \.self) { index in
        let arrival = reveal(time, start: 0.20 + Double(offset + index) * 0.026, duration: 0.38)
        Image(systemName: symbols[index])
          .font(.system(size: 19, weight: .regular))
          .foregroundStyle(.secondary.opacity(0.7))
          .frame(width: 42, height: 42)
          .background(.background.opacity(0.65), in: .rect(cornerRadius: 12))
          .opacity(arrival)
          .scaleEffect(0.95 + 0.05 * arrival)
          .offset(y: 7 * (1 - arrival))
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityHidden(true)
  }

  private func updatePlayback() {
    entrance.setActive(scenePhase == .active, reduceMotion: reduceMotion, now: .now)
  }

  private func reveal(_ time: TimeInterval, start: TimeInterval, duration: TimeInterval) -> Double {
    let value = min(1, max(0, (time - start) / duration))
    return value * value * (3 - 2 * value)
  }
}

/// A finite entrance retains its phase across inactive/background changes without a live idle loop.
struct HomeScreenEntranceClock {
  static let duration: TimeInterval = 0.95
  private(set) var elapsed: TimeInterval = 0
  private(set) var startedAt: Date?
  var isRunning: Bool { startedAt != nil }

  func time(at now: Date) -> TimeInterval {
    min(Self.duration, elapsed + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0))
  }

  mutating func setActive(_ active: Bool, reduceMotion: Bool, now: Date) {
    elapsed = time(at: now)
    startedAt = nil
    if reduceMotion {
      elapsed = Self.duration
    } else if active && elapsed < Self.duration {
      startedAt = now
    }
  }

  mutating func finish() {
    elapsed = Self.duration
    startedAt = nil
  }
}
