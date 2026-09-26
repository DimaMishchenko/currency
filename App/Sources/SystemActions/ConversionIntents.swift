import AppIntents
import Conversion
import CurrencyApplication
import Foundation

struct ConvertAmountIntent: AppIntent {
  static let title: LocalizedStringResource = "Convert amount"
  static let description = IntentDescription(
    "Convert an amount without changing your saved converter. Use ungrouped decimal text, such as 1234.56 or 1234,56."
  )
  static var supportedModes: IntentModes { .background }
  @Parameter(
    title: "Amount", description: "Ungrouped decimal text, for example 1234.56",
    requestValueDialog: "What amount would you like to convert?",
    resolvers: {
      NumericAmountText(); IntegerAmountText()
    }) var amount: String
  @Parameter(title: "From", query: CurrencyEntityQuery(allowsLocal: false)) var source:
    CurrencyEntity
  @Parameter(title: "To") var destination: CurrencyEntity
  @AppDependency private var composition: SystemActionComposition
  static var parameterSummary: some ParameterSummary {
    Summary("Convert \(\.$amount) from \(\.$source) to \(\.$destination)")
  }
  func perform() async throws -> some IntentResult & ReturnsValue<ConversionResultEntity>
    & ProvidesDialog
  {
    let evaluation = try await calculate(
      composition, amount: amount, source: source.id, destination: destination.id)
    return .result(
      value: ConversionResultEntity(result: evaluation.results[0], evaluation: evaluation),
      dialog: IntentDialog(stringLiteral: ConversionPresentation.speech(evaluation)))
  }
}

struct ConvertToMyCurrenciesIntent: AppIntent {
  static let title: LocalizedStringResource = "Convert to my currencies"
  static let description = IntentDescription(
    "Convert an amount to your current selected destinations, preserving their order and Local currency."
  )
  static var supportedModes: IntentModes { .background }
  @Parameter(
    title: "Amount", description: "Ungrouped decimal text, for example 1234.56",
    requestValueDialog: "What amount would you like to convert?",
    resolvers: {
      NumericAmountText(); IntegerAmountText()
    }) var amount: String
  @Parameter(title: "From", query: CurrencyEntityQuery(allowsLocal: false)) var source:
    CurrencyEntity
  @AppDependency private var composition: SystemActionComposition
  static var parameterSummary: some ParameterSummary {
    Summary("Convert \(\.$amount) from \(\.$source) to my currencies")
  }
  func perform() async throws -> some IntentResult & ReturnsValue<[ConversionResultEntity]>
    & ProvidesDialog
  {
    let evaluation = try await calculate(composition, amount: amount, source: source.id)
    return .result(
      value: evaluation.results.map { ConversionResultEntity(result: $0, evaluation: evaluation) },
      dialog: IntentDialog(stringLiteral: ConversionPresentation.speech(evaluation)))
  }
}

// Distinct shortcut adapters keep extraction and suggested phrases unambiguous.
struct ConvertToLocalIntent: AppIntent {
  static let title: LocalizedStringResource = "Convert to Local currency"
  static var supportedModes: IntentModes { .background }
  @Parameter(
    title: "Amount", description: "Ungrouped decimal text, for example 1234.56",
    requestValueDialog: "What amount would you like to convert?",
    resolvers: {
      NumericAmountText(); IntegerAmountText()
    }) var amount: String
  @Parameter(title: "From", query: CurrencyEntityQuery(allowsLocal: false)) var source:
    CurrencyEntity
  @AppDependency private var composition: SystemActionComposition
  static var parameterSummary: some ParameterSummary {
    Summary("Convert \(\.$amount) from \(\.$source) to Local currency")
  }
  func perform() async throws -> some IntentResult & ReturnsValue<ConversionResultEntity>
    & ProvidesDialog
  {
    let evaluation = try await calculate(
      composition, amount: amount, source: source.id, destination: CurrencySelection.localID)
    return .result(
      value: ConversionResultEntity(result: evaluation.results[0], evaluation: evaluation),
      dialog: IntentDialog(stringLiteral: ConversionPresentation.speech(evaluation)))
  }
}

struct CheckRateIntent: AppIntent {
  static let title: LocalizedStringResource = "Check exchange rate"
  static var supportedModes: IntentModes { .background }
  @Parameter(title: "From", query: CurrencyEntityQuery(allowsLocal: false)) var source:
    CurrencyEntity
  @Parameter(title: "To") var destination: CurrencyEntity
  @AppDependency private var composition: SystemActionComposition
  static var parameterSummary: some ParameterSummary {
    Summary("Check the rate from \(\.$source) to \(\.$destination)")
  }
  func perform() async throws -> some IntentResult & ReturnsValue<ConversionResultEntity>
    & ProvidesDialog
  {
    let evaluation = try await calculate(
      composition, amount: "1", source: source.id, destination: destination.id)
    return .result(
      value: ConversionResultEntity(result: evaluation.results[0], evaluation: evaluation),
      dialog: IntentDialog(stringLiteral: ConversionPresentation.speech(evaluation)))
  }
}

private func calculate(
  _ composition: SystemActionComposition, amount: String, source: String, destination: String? = nil
) async throws -> ConversionEvaluation {
  do {
    return try await composition.action.perform(
      composition.action.request(amount: amount, source: source, destination: destination))
  } catch let error as ConversionError { throw ConversionIntentError(error: error) }
}

struct ConversionIntentError: LocalizedError {
  let error: ConversionError
  var errorDescription: String? {
    switch error {
    case .invalidAmount:
      String(
        localized:
          "Enter a nonnegative amount without grouping, such as 1234.56. The amount must fit decimal precision."
      )
    case .unsupportedCurrency: String(localized: "Choose a supported currency.")
    case .noDestinations: String(localized: "Select destination currencies in Currency first.")
    case .localUnavailable:
      String(localized: "Local currency is unavailable. Set your location in Currency.")
    case .missingRates: String(localized: "The required exchange rates are unavailable.")
    case .overflow: String(localized: "This calculation exceeds decimal precision.")
    }
  }
}

/// Typed Number inputs bypass localized grouping; exact text never passes through Double.
struct NumericAmountText: Resolver {
  func resolve(from input: Double, context: IntentParameterContext<String>) async throws -> String?
  {
    guard input.isFinite, input >= 0,
      let value = Decimal(string: String(input), locale: Locale(identifier: "en_US_POSIX")),
      !value.isNaN, ExactAmount.parse(ExactAmount.string(value)) != nil
    else { throw ConversionIntentError(error: .invalidAmount) }
    return ExactAmount.string(value)
  }
}

struct IntegerAmountText: Resolver {
  func resolve(from input: Int, context: IntentParameterContext<String>) async throws -> String? {
    guard input >= 0 else { throw ConversionIntentError(error: .invalidAmount) }
    return String(input)
  }
}
