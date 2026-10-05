import AppIntents
import Conversion
import ExchangeRates
import Foundation

struct CurrencyEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Currency"
  static let defaultQuery = CurrencyEntityQuery()
  let id: String
  var displayRepresentation: DisplayRepresentation {
    .init(
      title: "\(id)",
      subtitle:
        "\(CurrencyCatalog.assetName(id) ?? Locale.current.localizedString(forCurrencyCode: id) ?? id)"
    )
  }
}

struct CurrencyEntityQuery: EntityStringQuery {
  @AppDependency private var composition: SystemActionComposition
  init() {}
  init(allowsLocal: Bool) {}
  func entities(for identifiers: [String]) async throws -> [CurrencyEntity] {
    identifiers.filter { CurrencyCode(rawValue: $0) != nil }.map { CurrencyEntity(id: $0) }
  }
  func suggestedEntities() async throws -> [CurrencyEntity] {
    var seen = Set<String>()
    return (composition.readSelected() + CurrencyCatalog.codes)
      .filter { seen.insert($0).inserted }.map { CurrencyEntity(id: $0) }
  }
  func entities(matching string: String) async throws -> [CurrencyEntity] {
    let allowed = Set(CurrencyCatalog.codes)
    return
      CurrencyCatalog.search(
        string, allowedCodes: allowed,
        name: {
          CurrencyCatalog.assetName($0) ?? Locale.current.localizedString(forCurrencyCode: $0) ?? $0
        }
      )
      .map { CurrencyEntity(id: $0) }
  }
}

struct ConversionResultEntity: TransientAppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Conversion result"
  let id = UUID()
  @Property(title: "Converted amount") var convertedAmount: String?
  @Property(title: "Currency") var currency: String?
  @Property(title: "Monetary amount") var monetaryAmount: IntentCurrencyAmount?
  @Property(title: "Result") var resultText: String
  @Property(title: "Status") var status: String
  init() {}
  init(
    result: ConversionResult, evaluation: ConversionEvaluation,
    style: ConversionPresentation.Style = .amount
  ) {
    convertedAmount = result.amount
    currency = result.destination.code
    if let code = currency, let asset = CurrencyCode(rawValue: code),
      !asset.isMetal, !asset.isCryptocurrency, asset != .xdr,
      Locale.Currency.isoCurrencies.contains(where: { $0.identifier == code }),
      let text = result.amount, let value = ExactAmount.parse(text)
    {
      monetaryAmount = IntentCurrencyAmount(amount: value, currencyCode: code)
    }
    resultText = ConversionPresentation.readable(result, request: evaluation.request, style: style)
    status = ConversionPresentation.status(evaluation, result: result)
  }
  var displayRepresentation: DisplayRepresentation {
    .init(title: "\(resultText)", subtitle: "\(status)")
  }
}

enum ConversionPresentation {
  enum Style { case amount, rate }
  static var localSetup: String { String(localized: "Choose a supported currency.") }
  static func readable(
    _ result: ConversionResult, request: ConversionRequest, style: Style
  ) -> String {
    guard let amount = result.amount, let quote = result.destination.code else {
      return String(localized: "Exchange rates are unavailable")
    }
    func label(_ text: String, code: String) -> String {
      let value = ExactAmount.parse(text)
      let step = Decimal(
        sign: .plus,
        exponent: -CurrencyPrecision.fractionDigits(code, metalUnit: request.metalUnit),
        significand: 1)
      let formatted: String
      if let value, value > 0, value < step {
        formatted = value.formatted(.number.precision(.significantDigits(1...6)))
      } else if let value {
        formatted = value.formatted(
          .number.precision(
            .fractionLength(
              0...CurrencyPrecision.fractionDigits(code, metalUnit: request.metalUnit))))
      } else {
        formatted = text
      }
      return CurrencyCatalog.metals.contains(code)
        ? "\(formatted) \(code) \(request.metalUnit.symbol)" : "\(formatted) \(code)"
    }
    return "\(label(request.amount, code: request.source)) ≈ \(label(amount, code: quote))"
  }
  static func status(_ evaluation: ConversionEvaluation, result: ConversionResult? = nil) -> String
  {
    var messages: [String] = []
    if result?.refreshFailed ?? evaluation.refreshFailed {
      messages.append(String(localized: "Some rates could not be refreshed"))
    }
    if result?.cacheIsStale ?? evaluation.cacheIsStale {
      messages.append(String(localized: "Using cached rates"))
    }
    if result?.dailyFallback ?? evaluation.dailyFallback {
      messages.append(String(localized: "Daily cryptocurrency rates"))
    }
    let results = result.map { [$0] } ?? evaluation.results
    let oldest =
      results.flatMap { [$0.sourceQuote?.published, $0.targetQuote?.published].compactMap { $0 } }
      .min()
    let today = evaluation.evaluatedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    if let oldest, oldest < today {
      messages.append(String(localized: "Includes rates from \(oldest)"))
    }
    return messages.joined(separator: ". ")
  }
  static func dialog(_ evaluation: ConversionEvaluation, style: Style = .amount) -> IntentDialog {
    var text = evaluation.results.map { readable($0, request: evaluation.request, style: style) }
      .joined(separator: "\n")
    let disclosure = status(evaluation)
    if !disclosure.isEmpty { text += "\n" + disclosure }
    return "\(text)"
  }
}
