import Conversion
import CoordinatedFiles
import Foundation

/// Coordinates the existing onboarding.json record independently of confirmed converter input.
public struct OnboardingProgressStore: Sendable {
  /// The explicitly supplied persistence directory.
  public let directory: URL

  /// Creates a progress store in an app container or an isolated fixture directory.
  public init(directory: URL) { self.directory = directory }

  /// Treats missing or corrupt progress as unfinished setup.
  public func load() -> OnboardingProgress? {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("onboarding.json"))
    else { return nil }
    return try? JSONDecoder().decode(OnboardingProgress.self, from: data)
  }

  /// Saves progress atomically under the same cross-process file coordination as prior versions.
  public func save(_ progress: OnboardingProgress) throws {
    let file = directory.appendingPathComponent("onboarding.json")
    try FileCoordination.write(at: file) {
      try JSONEncoder().encode(progress).write(to: file, options: .atomic)
    }
  }

  /// Starts replay from current choices only after the new draft has been committed.
  /// The preview amount never overwrites confirmed input or shared rates.
  public func restart(input: ConverterState) throws {
    var draft = input
    draft.setAmount("100")
    try save(OnboardingProgress(draft: draft, step: .welcome))
  }
}
