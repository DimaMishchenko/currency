import AppIntents
import Conversion
import ExchangeRates
import ExchangeRatesUI
import Foundation

struct ConversionResultEntity: TransientAppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Conversion result"
  let id: UUID
  @Property(title: "Converted amount") var convertedAmount: String?
  @Property(title: "Currency") var currency: String?
  @Property(title: "Monetary amount") var monetaryAmount: IntentCurrencyAmount?
  @Property(title: "Result") var resultText: String
  @Property(title: "Status") var status: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(resultText)", subtitle: "\(status)",
      image: currency.flatMap(CurrencyEntity.image))
  }
  init() { id = UUID() }
  init(
    result: ConversionResult, evaluation: ConversionEvaluation,
    style: ConversionPresentation.Style = .amount
  ) {
    id = UUID()
    convertedAmount = result.amount
    currency = result.destination.code
    resultText = ConversionPresentation.readable(result, request: evaluation.request, style: style)
    status = ConversionPresentation.status(evaluation, result: result)
    monetaryAmount = nil
    if let code = currency,
      Locale.Currency.isoCurrencies.contains(where: { $0.identifier == code }),
      let asset = CurrencyCode(rawValue: code), !asset.isMetal, !asset.isCryptocurrency,
      asset != .xdr,
      let text = result.amount, let value = ExactAmount.parse(text)
    {
      monetaryAmount = IntentCurrencyAmount(amount: value, currencyCode: code)
    }
  }
}

enum ConversionPresentation {
  enum Style { case amount, rate }
  static var localSetup: String {
    String(localized: "To use Local currency, open Currency and set up location.")
  }
  static func row(
    _ result: ConversionResult, request: ConversionRequest, style: Style = .amount,
    includesIcon: Bool = true
  ) -> String {
    guard let code = result.destination.code, let text = result.amount,
      let value = ExactAmount.parse(text)
    else {
      return result.id == CurrencySelection.localID
        ? String(localized: "Local currency")
        : String(localized: "\(result.destination.code ?? ""): unavailable")
    }
    let step = Decimal(sign: .plus, exponent: -CurrencyDisplay.fractionDigits(code), significand: 1)
    let formatted: String
    if style == .rate && value > 0 && value < step {
      let formatter = NumberFormatter()
      formatter.locale = .current; formatter.numberStyle = .decimal
      formatter.usesSignificantDigits = true; formatter.maximumSignificantDigits = 3
      formatted = formatter.string(from: NSDecimalNumber(decimal: value)) ?? text
    } else if value > 0 && value < step {
      formatted = String(localized: "Less than \(CurrencyDisplay.format(step, code: code))")
    } else {
      formatted = CurrencyDisplay.format(value, code: code)
    }
    let label = includesIcon ? "\(CurrencyDisplay.flag(code)) \(code)" : CurrencyDisplay.name(code)
    return CurrencyCode(rawValue: code)?.isMetal == true
      ? String(localized: "\(formatted) \(label) troy oz")
      : String(localized: "\(formatted) \(label)")
  }
  static func readable(
    _ result: ConversionResult, request: ConversionRequest, style: Style = .amount
  ) -> String {
    if result.amount == nil { return row(result, request: request, style: style) }
    let input = CurrencyDisplay.inputAmount(request.amount)
    let source = "\(CurrencyDisplay.flag(request.source)) \(request.source)"
    let output = row(result, request: request, style: style)
    let text =
      result.destination.code == request.source
      ? String(localized: "\(input) \(source) → \(output)")
      : String(localized: "\(input) \(source) → ≈ \(output)")
    return result.id == CurrencySelection.localID ? String(localized: "\(text) (Local)") : text
  }
  static func status(_ evaluation: ConversionEvaluation, result: ConversionResult? = nil) -> String
  {
    if let result {
      switch result.availability {
      case .localUnavailable: return localSetup
      case .missingRates: return String(localized: "Exchange rates are unavailable")
      case .overflow: return String(localized: "This calculation exceeds decimal precision")
      case .available: break
      }
      if result.destination.code == evaluation.request.source {
        return result.destination.localIsStale ? String(localized: "Last known Local currency") : ""
      }
    }
    var values: [String] = []
    if result?.refreshFailed ?? evaluation.refreshFailed {
      values.append(String(localized: "Some rates could not be refreshed"))
    }
    if result?.cacheIsStale ?? evaluation.cacheIsStale {
      values.append(String(localized: "Using cached rates"))
    }
    if result?.dailyFallback ?? evaluation.dailyFallback {
      values.append(String(localized: "Daily cryptocurrency rates"))
    }
    if result?.destination.localIsStale
      ?? evaluation.results.contains(where: { $0.destination.localIsStale })
    {
      values.append(String(localized: "Last known Local currency"))
    }
    if values.isEmpty {
      let relevant = result.map { [$0] } ?? evaluation.results
      let oldest =
        relevant.flatMap {
          [$0.sourceQuote?.published, $0.targetQuote?.published].compactMap { $0 }
        }
        .min()
      let today = evaluation.evaluatedAt.formatted(
        .iso8601.year().month().day().dateSeparator(.dash))
      if let oldest, oldest < today {
        values.append(
          String(localized: "Includes rates from \(CurrencyDisplay.publicationDate(oldest))"))
      }
    }
    return values.joined(separator: ". ")
  }
  static func speech(_ evaluation: ConversionEvaluation, style: Style = .amount) -> String {
    let available = evaluation.results.filter { $0.amount != nil }
    let missingLocal = evaluation.results.contains { $0.availability == .localUnavailable }
    if available.isEmpty {
      if evaluation.results.contains(where: { $0.availability == .overflow }) {
        return String(localized: "This amount is too large to convert. Try a smaller amount.")
      }
      return missingLocal
        ? localSetup
        : String(localized: "Exchange rates are unavailable. Open Currency to update them.")
    }
    let input = CurrencyDisplay.inputAmount(evaluation.request.amount)
    let source = CurrencyDisplay.name(evaluation.request.source)
    let rows = available.prefix(3)
      .map {
        row($0, request: evaluation.request, style: style, includesIcon: false)
      }
      .joined(separator: ", ")
    let identityOnly = available.allSatisfy { $0.destination.code == evaluation.request.source }
    var text =
      identityOnly
      ? String(localized: "\(input) \(source) is \(rows).")
      : String(localized: "\(input) \(source) is approximately \(rows).")
    let remaining = available.count - min(3, available.count)
    if remaining == 1 {
      text += " " + String(localized: "One more result is available.")
    } else if remaining > 1 {
      text += " " + String(localized: "\(remaining) more results are available.")
    }
    if missingLocal {
      text += " " + localSetup
    } else if available.count < evaluation.results.count {
      text += " " + String(localized: "Some conversions are unavailable.")
    }
    let message = status(evaluation)
    if !message.isEmpty { text += " " + message + "." }
    return text
  }
  static func dialog(_ evaluation: ConversionEvaluation, style: Style = .amount) -> IntentDialog {
    let speech = speech(evaluation, style: style)
    let rows = evaluation.results.prefix(3)
      .map {
        readable($0, request: evaluation.request, style: style)
      }
      .joined(separator: "\n")
    let supporting = evaluation.results.allSatisfy { $0.amount == nil } ? speech : rows
    return IntentDialog(full: "\(speech)", supporting: "\(supporting)")
  }
}
