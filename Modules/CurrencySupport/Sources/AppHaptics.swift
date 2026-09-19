import CoreHaptics
import UIKit

/// Shared tactile vocabulary. Only explicit actions and visible outcomes should call this.
@MainActor
public enum AppHaptics {
  /// Semantic feedback for user actions and their outcomes.
  public enum Cue {
    case selection, action, delete, success, warning, error
    case rotaryTick, chartReveal
    /// Two soft beats follow a currency swap or a scene's arrival.
    case transition
    /// A rising three-beat signature accompanies the onboarding finale.
    case celebration
  }

  private static let driver = Driver()

  /// Called by the app scene, never by a widget extension.
  public static func configure(active: Bool, reducedMotion: Bool) {
    driver.configure(active: active, reducedMotion: reducedMotion)
  }

  /// Plays a cue when the app is active, respecting the current motion preference.
  public static func play(_ cue: Cue) {
    driver.play(cue)
  }

  /// Stops only the named animation cue, leaving newer interactions intact.
  public static func stop(_ cue: Cue) { driver.stop(cue) }

  @MainActor
  private final class Driver {
    private let selection = UISelectionFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?
    private var currentCue: Cue?
    private var lastRotaryTick: ContinuousClock.Instant?
    private var lastSelection: ContinuousClock.Instant?
    private var active = true
    private var reducedMotion = false

    func configure(active: Bool, reducedMotion: Bool) {
      self.active = active
      self.reducedMotion = reducedMotion
      if !active {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop(completionHandler: nil)
      }
    }

    func stop(_ cue: Cue) {
      guard currentCue == cue else { return }
      try? player?.stop(atTime: CHHapticTimeImmediate)
      player = nil
      currentCue = nil
    }

    func play(_ cue: Cue) {
      guard active else { return }
      if cue == .selection {
        if let lastSelection, lastSelection.duration(to: .now) < .milliseconds(55) { return }
        lastSelection = .now
      }
      if cue == .rotaryTick {
        if let lastRotaryTick, lastRotaryTick.duration(to: .now) < .milliseconds(22) { return }
        lastRotaryTick = .now
      }
      // A new interaction replaces a pending flourish instead of stacking vibrations.
      try? player?.stop(atTime: CHHapticTimeImmediate)
      player = nil
      currentCue = cue
      switch cue {
      case .selection, .rotaryTick:
        selection.selectionChanged()
        selection.prepare()
      case .action: impact.impactOccurred(intensity: 0.85)
      case .delete: impact.impactOccurred(intensity: 1)
      case .success: notification.notificationOccurred(.success)
      case .warning: notification.notificationOccurred(.warning)
      case .error: notification.notificationOccurred(.error)
      case .transition, .celebration, .chartReveal:
        guard !reducedMotion, playPattern(cue) else {
          if cue == .celebration {
            notification.notificationOccurred(.success)
          } else {
            impact.impactOccurred(intensity: 0.85)
          }
          return
        }
      }
    }

    private func playPattern(_ cue: Cue) -> Bool {
      guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
      do {
        if engine == nil {
          let newEngine = try CHHapticEngine()
          newEngine.playsHapticsOnly = true
          newEngine.isAutoShutdownEnabled = true
          newEngine.resetHandler = { [weak self] in
            Task { @MainActor in
              self?.player = nil; self?.engine = nil
            }
          }
          engine = newEngine
        }
        guard let engine else { return false }
        // start() also handles auto-shutdown and interruptions; players are never reused.
        try engine.start()
        let beats: [(Double, Float, Float)]
        switch cue {
        case .celebration:
          beats = [(0, 0.4, 0.35), (0.16, 0.65, 0.5), (0.35, 0.9, 0.65)]
        case .chartReveal:
          // Follow the chart's 550 ms ease-out: close strokes opening into a final accent.
          beats = [
            (0, 0.4, 0.25), (0.045, 0.42, 0.3), (0.10, 0.45, 0.35),
            (0.17, 0.48, 0.4), (0.27, 0.5, 0.45), (0.40, 0.55, 0.5),
            (0.54, 0.7, 0.6)
          ]
        default:
          beats = [(0, 0.55, 0.4), (0.18, 0.4, 0.55)]
        }
        let events = beats.map { time, intensity, sharpness in
          CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
              CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
              CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ], relativeTime: time)
        }
        let pattern = try CHHapticPattern(events: events, parameters: [])
        let next = try engine.makePlayer(with: pattern)
        player = next
        try next.start(atTime: CHHapticTimeImmediate)
        return true
      } catch {
        player = nil
        engine = nil
        return false
      }
    }
  }
}
