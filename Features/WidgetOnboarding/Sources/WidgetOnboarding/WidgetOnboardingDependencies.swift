/// Semantic requests interpreted by application coordination.
public enum WidgetOnboardingOutput: Sendable { case locationRequested, closed }

/// The host owns transitions to other features. Demonstration state stays local.
@MainActor
public struct WidgetOnboardingDependencies {
  /// Receives semantic outcomes and requests for application coordination.
  public var output: (WidgetOnboardingOutput) -> Void
  /// Supplies the host handling of cross-feature requests.
  public init(output: @escaping (WidgetOnboardingOutput) -> Void) { self.output = output }
}
