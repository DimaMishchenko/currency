import Foundation

/// Retains a Settings flow while its entry is covered by feature-local navigation.
/// Hosts with explicit teardown ownership call stop; releasing the token also cancels its work.
@MainActor
public final class SettingsFlowLifetime {
  /// The single model retained for this flow identity.
  public let model: SettingsModel
  private var task: Task<Void, Never>?
  private var stopped = false

  /// Constructs a dormant flow with explicit capabilities.
  public init(dependencies: SettingsDependencies) {
    model = SettingsModel(dependencies: dependencies)
  }

  /// Starts observation once. Reappearing after a child screen does not replace the subscription.
  public func start() {
    guard !stopped, task == nil else { return }
    let model = model
    // Capture only the model: retaining this token here would prevent its teardown.
    task = Task { await model.run() }
  }

  /// Ends the flow explicitly and cancels any outstanding refresh before releasing observation.
  public func stop() {
    guard !stopped else { return }
    stopped = true
    task?.cancel()
    task = nil
    model.stop()
  }

  isolated deinit {
    task?.cancel()
    model.stop()
  }
}
