import Conversion
import Foundation

/// Resumable onboarding state is distinct from converter input and final completion.
public struct OnboardingProgress: Codable, Sendable {
  /// The resumable scenes encoded in the onboarding progress record.
  public enum Step: String, Codable, Sendable {
    case welcome, baseCurrency, selection, homeScreen, widgets, ready
  }
  /// The onboarding schema and experience version.
  public var version: Int
  /// The unfinished, ordered currency choices.
  public var draft: ConverterState
  /// The last persisted scene.
  public var step: Step
  /// Whether final completion was successfully committed.
  public var completed: Bool

  /// Creates a resumable progress record without mutating converter input.
  public init(
    version: Int = 1, draft: ConverterState, step: Step = .welcome,
    completed: Bool = false
  ) {
    self.version = version
    self.draft = draft
    self.step = step
    self.completed = completed
  }
}
