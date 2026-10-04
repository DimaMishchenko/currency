import Foundation

/// Aggregates scene activity for the single process-wide haptic driver.
struct HapticSceneActivity {
  private struct Scene { let reducedMotion: Bool }
  private var activeScenes: [UUID: Scene] = [:]
  var active: Bool { !activeScenes.isEmpty }
  /// Use the most restrictive preference among active scenes for shared decorative feedback.
  var reducedMotion: Bool { activeScenes.values.contains { $0.reducedMotion } }

  mutating func configure(sceneID: UUID, active: Bool, reducedMotion: Bool) {
    activeScenes[sceneID] = active ? Scene(reducedMotion: reducedMotion) : nil
  }
  mutating func remove(sceneID: UUID) { activeScenes.removeValue(forKey: sceneID) }
}
