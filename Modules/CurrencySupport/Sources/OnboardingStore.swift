import ExchangeRates
import Foundation

/// Resumable onboarding state is distinct from converter input and final completion.
public struct OnboardingProgress: Codable, Sendable {
  /// The resumable scenes encoded in the onboarding progress record.
  public enum Step: String, Codable, Sendable {
    case welcome, baseCurrency, selection, homeScreen, widgets
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

extension CurrencyStore {
  /// Loads progress, treating a missing or corrupt record as unfinished setup.
  public func onboardingProgress() -> OnboardingProgress? {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("onboarding.json"))
    else { return nil }
    return try? JSONDecoder().decode(OnboardingProgress.self, from: data)
  }

  /// Atomically persists the draft, stage, and separate completion flag.
  public func saveOnboardingProgress(_ progress: OnboardingProgress) throws {
    try coordinate("onboarding.json") {
      try JSONEncoder().encode(progress)
        .write(to: directory.appendingPathComponent("onboarding.json"), options: .atomic)
    }
  }

  /// Atomically merges a progressive refresh with quotes committed by another host.
  public func saveBootstrapRates(_ snapshot: RateSnapshot, now: Date = .now) throws -> RateSnapshot
  {
    try coordinate("rates.json") {
      // The incoming snapshot wins equal-attempt ties: it includes later provider deliveries.
      let saved = loadRates()
      let current = saved.hasValidFetchTimestamp(now: now) ? saved : RateSnapshot()
      let merged = snapshot.merging(current)
      try RateCache(directory: directory).save(merged)
      return merged
    }
  }
}
