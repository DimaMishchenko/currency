import Foundation

/// Analytic deceleration keeps momentum independent of rendering frequency.
public struct CurrencyOrbitMotion {
  private var offset: Double = 0
  private var releasedAt: TimeInterval = 0
  private var velocity: Double = 0
  private var held = false
  private var drift: Double

  /// Creates an orbit with an idle rotation speed in radians per second.
  public init(drift: Double = Double.pi * 2 / 32) { self.drift = drift }
  private let friction = 1.7

  /// Returns the angle for a timestamp on the caller's animation clock.
  public func angle(at time: TimeInterval) -> Double {
    guard !held else { return offset }
    let duration = max(0, time - releasedAt)
    return offset + drift * duration + velocity * (1 - exp(-friction * duration)) / friction
  }

  /// Decorative drift stays silent; only a held or decelerating user spin ticks.
  public func hasUserMomentum(at time: TimeInterval) -> Bool {
    held || abs(velocity) * exp(-friction * max(0, time - releasedAt)) > 0.25
  }

  /// Changes the idle rotation speed without jumping or restarting user momentum.
  public mutating func setDrift(_ drift: Double, at time: TimeInterval) {
    offset = angle(at: time)
    velocity *= exp(-friction * max(0, time - releasedAt))
    releasedAt = time
    self.drift = drift
  }

  /// Stops drift and momentum at the current angle for direct manipulation.
  public mutating func grab(at time: TimeInterval) {
    offset = angle(at: time)
    held = true
    velocity = 0
  }

  /// Applies a drag increment in radians.
  public mutating func turn(by angle: Double) { offset += angle }

  /// Releases a held orbit with a velocity in radians per second.
  public mutating func release(at time: TimeInterval, velocity: Double) {
    guard held else { return }
    releasedAt = time
    self.velocity = velocity
    held = false
  }

  /// Returns the signed angular distance without a discontinuity at a full turn.
  public static func shortestTurn(from start: Double, to end: Double) -> Double {
    atan2(sin(end - start), cos(end - start))
  }
}
