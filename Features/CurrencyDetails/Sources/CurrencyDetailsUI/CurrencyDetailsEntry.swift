import CurrencyDetails
import Foundation
import SwiftUI

private struct CurrencyDetailsDependenciesKey: EnvironmentKey {
  static let defaultValue: CurrencyDetailsDependencies? = nil
}

extension EnvironmentValues {
  /// Required history loading, captured by the details model at the entry boundary.
  public var currencyDetailsDependencies: CurrencyDetailsDependencies? {
    get { self[CurrencyDetailsDependenciesKey.self] }
    set { self[CurrencyDetailsDependenciesKey.self] = newValue }
  }
}

/// Production details entry with a stable model for each supplied flow identity.
public struct CurrencyDetailsEntry: View {
  @Environment(\.currencyDetailsDependencies) private var dependencies
  private let flowID: UUID
  private let input: CurrencyDetailsInput

  /// Creates details without implicitly constructing a history service.
  public init(flowID: UUID, input: CurrencyDetailsInput) {
    self.flowID = flowID
    self.input = input
  }

  /// Resolves history operations at the UI boundary.
  public var body: some View {
    if let dependencies {
      CurrencyDetailsContent(input: input, dependencies: dependencies).id(flowID)
    } else {
      missingDependencies()
    }
  }

  private func missingDependencies() -> Never {
    preconditionFailure(
      "CurrencyDetailsEntry requires currencyDetailsDependencies in its environment")
  }
}

private struct CurrencyDetailsContent: View {
  @State private var model: CurrencyDetailsModel

  init(input: CurrencyDetailsInput, dependencies: CurrencyDetailsDependencies) {
    _model = State(initialValue: CurrencyDetailsModel(input: input, dependencies: dependencies))
  }

  var body: some View { RateDetailsScreen(model: model) }
}
