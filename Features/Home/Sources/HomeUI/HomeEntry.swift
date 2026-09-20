import Conversion
import DesignSystem
import ExchangeRatesUI
import Home
import SwiftUI

private struct HomeDependenciesKey: EnvironmentKey {
  static let defaultValue: HomeDependencies? = nil
}
public extension EnvironmentValues {
  /// Required Home operations, resolved at the feature entry.
  var homeDependencies: HomeDependencies? {
    get { self[HomeDependenciesKey.self] }
    set { self[HomeDependenciesKey.self] = newValue }
  }
}

/// Production workspace entry retaining one model for each scene flow identity.
public struct HomeEntry: View {
  @Environment(\.homeDependencies) private var dependencies
  private let flowID: UUID
  private let active: Bool
  private let detailsNamespace: Namespace.ID
  private let onOutput: (HomeOutput) -> Void

  /// Creates an entry with explicit activity and application-owned output handling.
  public init(
    flowID: UUID, active: Bool, detailsNamespace: Namespace.ID,
    onOutput: @escaping (HomeOutput) -> Void
  ) {
    self.flowID = flowID; self.active = active
    self.detailsNamespace = detailsNamespace; self.onOutput = onOutput
  }
  /// Resolves required dependencies and constructs the flow host.
  public var body: some View {
    if let dependencies {
      HomeHost(
        dependencies: dependencies, active: active, detailsNamespace: detailsNamespace,
        onOutput: onOutput
      )
      .id(flowID)
    } else {
      missingDependencies()
    }
  }
  private func missingDependencies() -> Never {
    preconditionFailure("HomeEntry requires homeDependencies")
  }
}

private struct HomeHost: View {
  @State private var model: HomeModel
  let active: Bool
  let detailsNamespace: Namespace.ID
  let onOutput: (HomeOutput) -> Void
  init(
    dependencies: HomeDependencies, active: Bool, detailsNamespace: Namespace.ID,
    onOutput: @escaping (HomeOutput) -> Void
  ) {
    self.active = active
    self.detailsNamespace = detailsNamespace; self.onOutput = onOutput
    _model = State(initialValue: HomeModel(dependencies: dependencies))
  }
  var body: some View {
    HomeScreen(model: model, detailsMotion: detailsNamespace, onOutput: onOutput)
      .task(id: active) {
        guard active else { return }
        await model.observeChanges()
      }
  }
}

extension HomeModel {
  var warningText: LocalizedStringResource? {
    switch warning {
    case .selectionSaveFailed: .Converter.selectionSaveFailed
    case .rateSaveFailed: .Converter.rateSaveFailed
    case .rateWarning(let warning): RateMessages.refresh(warning)
    case nil: nil
    }
  }
  @discardableResult
  func updateWithFeedback(_ mutation: (inout Conversion.ConverterState) throws -> Void) -> Bool {
    let saved = updateInput(mutation)
    if !saved { AppHaptics.play(.error) }
    return saved
  }
}
