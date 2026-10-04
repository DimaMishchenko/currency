import Foundation
import Testing

@testable import DesignSystem

struct HapticSceneActivityTests {
  @Test func inactiveOrRemovedSceneCannotDisableAnotherActiveScene() {
    var activity = HapticSceneActivity()
    let first = UUID()
    let second = UUID()
    activity.configure(sceneID: first, active: true, reducedMotion: false)
    activity.configure(sceneID: second, active: true, reducedMotion: true)
    #expect(activity.active)
    #expect(activity.reducedMotion)
    activity.configure(sceneID: second, active: false, reducedMotion: true)
    #expect(activity.active)
    #expect(!activity.reducedMotion)
    activity.remove(sceneID: second)
    #expect(activity.active)
    activity.remove(sceneID: first)
    #expect(!activity.active)
  }

  @Test func preferenceChangeIsAppliedOnlyForActiveScenes() {
    var activity = HapticSceneActivity()
    let first = UUID()
    let second = UUID()
    activity.configure(sceneID: first, active: true, reducedMotion: false)
    activity.configure(sceneID: second, active: false, reducedMotion: true)
    #expect(!activity.reducedMotion)
    activity.configure(sceneID: first, active: true, reducedMotion: true)
    #expect(activity.reducedMotion)
  }
}
