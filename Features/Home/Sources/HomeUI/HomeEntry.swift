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
  private let discoveryVisitID: UUID
  private let discoveryIdle: Bool
  private let detailsNamespace: Namespace.ID
  private let widgetsNamespace: Namespace.ID
  private let onOutput: (HomeOutput) -> Void
  private let currencyDecoration: (String, AnyView) -> AnyView

  /// Creates an entry with explicit activity and application-owned output handling.
  public init(
    flowID: UUID, active: Bool, discoveryVisitID: UUID, discoveryIdle: Bool,
    detailsNamespace: Namespace.ID,
    widgetsNamespace: Namespace.ID,
    currencyDecoration: @escaping (String, AnyView) -> AnyView = { _, content in content },
    onOutput: @escaping (HomeOutput) -> Void
  ) {
    self.flowID = flowID; self.active = active
    self.discoveryVisitID = discoveryVisitID
    self.discoveryIdle = discoveryIdle
    self.detailsNamespace = detailsNamespace; self.widgetsNamespace = widgetsNamespace
    self.onOutput = onOutput
    self.currencyDecoration = currencyDecoration
  }
  /// Resolves required dependencies and constructs the flow host.
  public var body: some View {
    if let dependencies {
      HomeHost(
        dependencies: dependencies, active: active, discoveryVisitID: discoveryVisitID,
        discoveryIdle: discoveryIdle,
        detailsNamespace: detailsNamespace,
        widgetsNamespace: widgetsNamespace,
        currencyDecoration: currencyDecoration,
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
  let discoveryVisitID: UUID
  let discoveryIdle: Bool
  let detailsNamespace: Namespace.ID
  let widgetsNamespace: Namespace.ID
  let onOutput: (HomeOutput) -> Void
  let currencyDecoration: (String, AnyView) -> AnyView
  init(
    dependencies: HomeDependencies, active: Bool, discoveryVisitID: UUID, discoveryIdle: Bool,
    detailsNamespace: Namespace.ID,
    widgetsNamespace: Namespace.ID,
    currencyDecoration: @escaping (String, AnyView) -> AnyView,
    onOutput: @escaping (HomeOutput) -> Void
  ) {
    self.active = active
    self.discoveryVisitID = discoveryVisitID
    self.discoveryIdle = discoveryIdle
    self.detailsNamespace = detailsNamespace; self.widgetsNamespace = widgetsNamespace
    self.onOutput = onOutput
    self.currencyDecoration = currencyDecoration
    _model = State(initialValue: HomeModel(dependencies: dependencies))
  }
  var body: some View {
    HomeScreen(
      model: model, active: active, discoveryIdle: discoveryIdle,
      detailsMotion: detailsNamespace, widgetsMotion: widgetsNamespace,
      currencyDecoration: currencyDecoration,
      onOutput: onOutput
    )
    .task(id: active) {
      guard active else { return }
      model.beginDiscoveryVisit(id: discoveryVisitID)
      await model.observeChanges()
    }
    .onChange(of: discoveryVisitID) { _, id in
      if active { model.beginDiscoveryVisit(id: id) }
    }
    .onChange(of: active) { _, value in
      if !value { model.endDiscoveryVisit() }
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
  func withFeedback(_ action: () -> Bool) -> Bool {
    let saved = action()
    if !saved { AppHaptics.play(.error) }
    return saved
  }
}
