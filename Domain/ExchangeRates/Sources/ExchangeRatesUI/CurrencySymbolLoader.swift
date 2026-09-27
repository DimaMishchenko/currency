import SwiftUI

/// One fixed optical box; the supported symbol replacement has a standard fallback.
public struct CurrencySymbolLoader: View {
  private let requestedMotion: Bool
  private let animateImmediately: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  private let interval: Duration
  /// Creates the automatic symbol cycle used during bootstrap.
  public init(
    moving: Bool, interval: Duration = .milliseconds(720), animateImmediately: Bool = false
  ) {
    requestedMotion = moving
    self.interval = interval
    self.animateImmediately = animateImmediately
  }
  private var moving: Bool { requestedMotion && !reduceMotion && scenePhase == .active }
  @State private var index = 1
  private let symbols = ["dollarsign", "eurosign", "sterlingsign", "yensign"]
  /// The fixed-size currency symbol presentation.
  public var body: some View {
    Image(systemName: symbols[index])
      .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
      .font(.system(size: 26, weight: .medium, design: .rounded))
      .frame(width: 40, height: 40)
      .accessibilityHidden(true)
      .task(id: moving ? interval : .zero) {
        guard moving else { return }
        if animateImmediately {
          withAnimation(.easeInOut(duration: 0.28)) { index = (index + 1) % symbols.count }
        }
        while !Task.isCancelled {
          do { try await Task.sleep(for: interval) } catch { return }
          withAnimation(.easeInOut(duration: 0.28)) { index = (index + 1) % symbols.count }
        }
      }
  }
}
