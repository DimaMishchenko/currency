import AppIntents
import CurrencyApplication
import Foundation

struct OpenCurrencyIntent: AppIntent {
  static let title: LocalizedStringResource = "Open currency details"
  static var supportedModes: IntentModes { .foreground(.immediate) }
  @Parameter(title: "Currency", query: CurrencyEntityQuery(selectedOnly: true)) var target:
    CurrencyEntity
  @AppDependency private var composition: SystemActionComposition
  func perform() async throws -> some IntentResult & OpensIntent {
    guard composition.readSelected().contains(target.id) else {
      throw SelectedCurrencyUnavailable()
    }
    guard let url = CurrencyRoute.currency(target.id).url else {
      throw SelectedCurrencyUnavailable()
    }
    return .result(opensIntent: OpenURLIntent(url))
  }
}

@available(iOS 27.0, *)
@AppIntent(schema: .system.open)
struct OpenCurrencyWithSiriIntent: AppIntent {
  static let title: LocalizedStringResource = "Open selected currency"
  static var supportedModes: IntentModes { .foreground(.immediate) }
  @Parameter(title: "Currency", query: CurrencyEntityQuery(selectedOnly: true)) var target:
    CurrencyEntity
  @AppDependency private var composition: SystemActionComposition
  func perform() async throws -> some IntentResult & OpensIntent {
    guard composition.readSelected().contains(target.id) else {
      throw SelectedCurrencyUnavailable()
    }
    guard let url = CurrencyRoute.currency(target.id).url else {
      throw SelectedCurrencyUnavailable()
    }
    return .result(opensIntent: OpenURLIntent(url))
  }
}

struct SelectedCurrencyUnavailable: LocalizedError {
  var errorDescription: String? {
    String(localized: "This currency is no longer selected in Currency.")
  }
}
