import AppIntents

struct OpenCurrencyIntent: OpenIntent, TargetContentProvidingIntent {
  static let title: LocalizedStringResource = "Open currency details"
  static let description = IntentDescription(
    "See a currency’s exchange rate and history in Currency.")
  @Parameter(
    title: "Currency", requestValueDialog: "Which currency would you like to open?"
  ) var target: CurrencyEntity
  static var parameterSummary: some ParameterSummary {
    Summary("Open details for \(\.$target)")
  }
}
