import AppIntents
import Conversion
import CurrencyApplication
import Foundation

struct ConvertAmountIntent: AppIntent {
  static let title: LocalizedStringResource = "Convert amount"
  static let description = IntentDescription(
    "Convert an amount between currencies, crypto or metals."
  )
  static var supportedModes: IntentModes { .background }
  @Parameter(
    title: "Amount", description: "The amount to convert.",
    requestValueDialog: "What amount would you like to convert?",
    resolvers: {
      NumericAmountText(); IntegerAmountText()
    }) var amount: String
  @Parameter(
    title: "From", requestValueDialog: "Which currency are you converting from?",
    requestDisambiguationDialog: "Which source currency did you mean?",
    query: CurrencyEntityQuery(allowsLocal: false)
  ) var source: CurrencyEntity
  @Parameter(
    title: "To", requestValueDialog: "Which currency are you converting to?",
    requestDisambiguationDialog: "Which destination currency did you mean?"
  ) var destination: CurrencyEntity
  @AppDependency private var composition: SystemActionComposition
  static var parameterSummary: some ParameterSummary {
    Summary("Convert \(\.$amount) from \(\.$source) to \(\.$destination)")
  }
  func perform() async throws -> some IntentResult & ReturnsValue<ConversionResultEntity>
    & ProvidesDialog
  {
    guard ExactAmount.parse(amount) != nil else {
      throw $amount.needsValueError("Enter an amount without grouping, such as 100 or 12.50.")
    }
    let evaluation = try await calculate(
      composition, amount: amount, source: source.id, destination: destination.id)
    return .result(
      value: ConversionResultEntity(result: evaluation.results[0], evaluation: evaluation),
      dialog: ConversionPresentation.dialog(evaluation))
  }
}

struct ConvertToMyCurrenciesIntent: AppIntent {
  static let title: LocalizedStringResource = "Convert to my currencies"
  static let description = IntentDescription(
    "Convert an amount to the currencies you’ve chosen in Currency."
  )
  static var supportedModes: IntentModes { .background }
  @Parameter(
    title: "Amount", description: "The amount to convert.",
    requestValueDialog: "What amount would you like to convert?",
    resolvers: {
      NumericAmountText(); IntegerAmountText()
    }) var amount: String
  @Parameter(
    title: "From", requestValueDialog: "Which currency are you converting from?",
    requestDisambiguationDialog: "Which source currency did you mean?",
    query: CurrencyEntityQuery(allowsLocal: false)
  ) var source: CurrencyEntity
  @AppDependency private var composition: SystemActionComposition
  static var parameterSummary: some ParameterSummary {
    Summary("Convert \(\.$amount) from \(\.$source) to my currencies")
  }
  func perform() async throws -> some IntentResult & ReturnsValue<[ConversionResultEntity]>
    & ProvidesDialog
  {
    guard ExactAmount.parse(amount) != nil else {
      throw $amount.needsValueError("Enter an amount without grouping, such as 100 or 12.50.")
    }
    let evaluation = try await calculate(composition, amount: amount, source: source.id)
    return .result(
      value: evaluation.results.map { ConversionResultEntity(result: $0, evaluation: evaluation) },
      dialog: ConversionPresentation.dialog(evaluation))
  }
}

#if os(iOS)
  struct ConvertToLocalIntent: AppIntent {
    static let title: LocalizedStringResource = "Convert to Local currency"
    static let description = IntentDescription(
      "Convert an amount to the currency for your location.")
    static var supportedModes: IntentModes { .background }
    @Parameter(
      title: "Amount", description: "The amount to convert.",
      requestValueDialog: "What amount would you like to convert?",
      resolvers: {
        NumericAmountText(); IntegerAmountText()
      }) var amount: String
    @Parameter(
      title: "From", requestValueDialog: "Which currency are you converting from?",
      requestDisambiguationDialog: "Which source currency did you mean?",
      query: CurrencyEntityQuery(allowsLocal: false)
    ) var source: CurrencyEntity
    @AppDependency private var composition: SystemActionComposition
    static var parameterSummary: some ParameterSummary {
      Summary("Convert \(\.$amount) from \(\.$source) to Local currency")
    }
    func perform() async throws -> some IntentResult & ReturnsValue<ConversionResultEntity>
      & ProvidesDialog
    {
      guard ExactAmount.parse(amount) != nil else {
        throw $amount.needsValueError("Enter an amount without grouping, such as 100 or 12.50.")
      }
      let evaluation = try await calculate(
        composition, amount: amount, source: source.id, destination: CurrencySelection.localID)
      return .result(
        value: ConversionResultEntity(result: evaluation.results[0], evaluation: evaluation),
        dialog: ConversionPresentation.dialog(evaluation))
    }
  }

#endif

struct CheckRateIntent: AppIntent {
  static let title: LocalizedStringResource = "Check exchange rate"
  static let description = IntentDescription("See how much one unit is worth in another currency.")
  static var supportedModes: IntentModes { .background }
  @Parameter(
    title: "From", requestValueDialog: "Which currency are you converting from?",
    requestDisambiguationDialog: "Which source currency did you mean?",
    query: CurrencyEntityQuery(allowsLocal: false)
  ) var source: CurrencyEntity
  @Parameter(
    title: "To", requestValueDialog: "Which currency are you converting to?",
    requestDisambiguationDialog: "Which destination currency did you mean?"
  ) var destination: CurrencyEntity
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
      value: ConversionResultEntity(
        result: evaluation.results[0], evaluation: evaluation, style: .rate),
      dialog: ConversionPresentation.dialog(evaluation, style: .rate))
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
      String(localized: "Enter an amount without grouping, such as 100 or 12.50.")
    case .unsupportedCurrency: String(localized: "Choose a supported currency.")
    case .noDestinations: String(localized: "Select destination currencies in Currency first.")
    case .localUnavailable:
      ConversionPresentation.localSetup
    case .missingRates: String(localized: "The required exchange rates are unavailable.")
    case .overflow: String(localized: "This calculation exceeds decimal precision.")
    }
  }
}

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
