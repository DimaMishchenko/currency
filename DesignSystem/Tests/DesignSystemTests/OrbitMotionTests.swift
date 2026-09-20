import DesignSystem
import Foundation
import Testing

@Suite struct OrbitMotionTests {
  @Test func changingOrbitSpeedPreservesPositionAndUserMomentum() {
    guard #available(iOS 26.0, *) else { return }
    var orbit = CurrencyOrbitMotion(drift: 1 / 18)
    orbit.grab(at: 1)
    orbit.turn(by: 0.8)
    orbit.release(at: 1, velocity: 6)
    let before = orbit.angle(at: 1.5)
    orbit.setDrift(1 / 6, at: 1.5)
    #expect(abs(orbit.angle(at: 1.5) - before) < 0.000001)
    #expect(orbit.hasUserMomentum(at: 1.5))
    orbit.grab(at: 2)
    let held = orbit.angle(at: 2)
    orbit.setDrift(0, at: 2)
    #expect(orbit.angle(at: 10) == held)
    orbit.turn(by: 0.3)
    orbit.release(at: 10, velocity: 0)
    #expect(abs(orbit.angle(at: 20) - held - 0.3) < 0.000001)
    #expect(!orbit.hasUserMomentum(at: 20))
  }

  @Test func tactileMomentumEndsBeforeDecorativeDrift() {
    guard #available(iOS 26.0, *) else { return }
    var orbit = CurrencyOrbitMotion()
    #expect(!orbit.hasUserMomentum(at: 20))
    orbit.grab(at: 20)
    #expect(orbit.hasUserMomentum(at: 20))
    orbit.release(at: 20, velocity: -10)
    #expect(orbit.hasUserMomentum(at: 20.5))
    #expect(!orbit.hasUserMomentum(at: 25))
    orbit.grab(at: 25)
    orbit.release(at: 25, velocity: 0)
    #expect(!orbit.hasUserMomentum(at: 25))
  }

  @Test func crossingAngleBoundaryKeepsDragContinuous() {
    guard #available(iOS 26.0, *) else { return }
    let turn = CurrencyOrbitMotion.shortestTurn(from: .pi - 0.02, to: -.pi + 0.02)
    #expect(abs(turn - 0.04) < 0.000001)
    #expect(
      abs(CurrencyOrbitMotion.shortestTurn(from: -.pi + 0.02, to: .pi - 0.02) + 0.04) < 0.000001)
  }

  @Test func grabbingMovingOrbitDoesNotJumpAndStopsDriftWhileHeld() {
    guard #available(iOS 26.0, *) else { return }
    var orbit = CurrencyOrbitMotion()
    let before = orbit.angle(at: 10)
    orbit.grab(at: 10)
    #expect(orbit.angle(at: 10) == before)
    #expect(orbit.angle(at: 30) == before)
    orbit.turn(by: -0.7)
    #expect(abs(orbit.angle(at: 30) - (before - 0.7)) < 0.000001)
    orbit.release(at: 30, velocity: -8)
    #expect(abs(orbit.angle(at: 30) - (before - 0.7)) < 0.000001)
  }

  @Test func flickWorksInBothDirectionsAndDecaysToAmbientSpeed() {
    guard #available(iOS 26.0, *) else { return }
    for direction in [-1.0, 1.0] {
      var orbit = CurrencyOrbitMotion()
      orbit.grab(at: 0)
      orbit.release(at: 0, velocity: direction * 10)
      let first = orbit.angle(at: 0.1) - orbit.angle(at: 0)
      #expect(first * direction > 0)
      let late = orbit.angle(at: 10.1) - orbit.angle(at: 10)
      #expect(abs(late - Double.pi * 2 / 32 * 0.1) < 0.00001)
    }
  }

  @Test func grabbingDuringMomentumContinuesFromRenderedPosition() {
    guard #available(iOS 26.0, *) else { return }
    var orbit = CurrencyOrbitMotion()
    orbit.grab(at: 0)
    orbit.release(at: 0, velocity: 12)
    let rendered = orbit.angle(at: 0.4)
    orbit.grab(at: 0.4)
    #expect(orbit.angle(at: 0.4) == rendered)
    orbit.turn(by: 0.3)
    orbit.release(at: 0.8, velocity: 0)
    #expect(abs(orbit.angle(at: 0.8) - rendered - 0.3) < 0.000001)
  }
}
