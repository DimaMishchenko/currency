import Conversion
import ExchangeRates
import Foundation

/// The operations used by one resumable setup flow; composition supplies live or controlled values.
@MainActor
public struct OnboardingDependencies {
  /// Restores the feature-owned progress record.
  public var loadProgress: () -> OnboardingProgress?
  /// Commits draft, stage, or completion before a successful transition.
  public var saveProgress: (OnboardingProgress) throws -> Void
  /// Reads confirmed input without changing it.
  public var readInput: () -> ConverterState
  /// Edits freshly loaded confirmed input under the storage owner's coordination.
  public var editInput: ((inout ConverterState) -> Void) throws -> Void
  /// Reads the most recently committed shared rates.
  public var readRates: () -> RateSnapshot
  /// Merges a progressive snapshot with concurrent writes and returns the committed result.
  public var saveRates: (RateSnapshot, Date) throws -> RateSnapshot
  /// Streams progressive provider results; the model rejects superseded attempt identities.
  public var bootstrap: (RateSnapshot, Date) async -> AsyncStream<BootstrapUpdate>
  /// Supplies the clock used for quote validity.
  public var now: () -> Date

  /// Creates required setup operations without selecting any implicit live implementation.
  public init(
    loadProgress: @escaping () -> OnboardingProgress?,
    saveProgress: @escaping (OnboardingProgress) throws -> Void,
    readInput: @escaping () -> ConverterState,
    editInput: @escaping ((inout ConverterState) -> Void) throws -> Void,
    readRates: @escaping () -> RateSnapshot,
    saveRates: @escaping (RateSnapshot, Date) throws -> RateSnapshot,
    bootstrap: @escaping (RateSnapshot, Date) async -> AsyncStream<BootstrapUpdate>,
    now: @escaping () -> Date
  ) {
    self.loadProgress = loadProgress
    self.saveProgress = saveProgress
    self.readInput = readInput
    self.editInput = editInput
    self.readRates = readRates
    self.saveRates = saveRates
    self.bootstrap = bootstrap
    self.now = now
  }
}

/// Outcomes interpreted by the application's scene coordinator.
public enum OnboardingOutput: Sendable, Equatable {
  /// The ready finale is visible, allowing the application to preload its next presentation.
  case finalePresented
  /// Completion has been committed successfully.
  case completed
}
