import AppIntents
import Conversion
import ExchangeRates
import ExchangeRatesUI
import Foundation

/// System-rendered output with precise chaining values and concise human-readable context.
struct ConversionResultEntity: TransientAppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Conversion result"
  let id: UUID
  @Property(title: "Converted amount") var convertedAmount: String?
  @Property(title: "Currency") var currency: String?
  @Property(title: "Monetary amount") var monetaryAmount: IntentCurrencyAmount?
  @Property(title: "Result") var resultText: String
  @Property(title: "Status") var status: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(resultText)", subtitle: "\(status)")
  }
  init() { id = UUID() }
  init(result: ConversionResult, evaluation: ConversionEvaluation) {
    id = UUID()
    convertedAmount = result.amount
    currency = result.destination.code
    resultText = ConversionPresentation.readable(result, request: evaluation.request)
    status = ConversionPresentation.status(evaluation, result: result)
    monetaryAmount = nil
    if let code = currency,
      Locale.Currency.isoCurrencies.contains(where: { $0.identifier == code }),
      !["XAU", "XAG", "XPT", "XPD", "XDR"].contains(code), !CurrencyCatalog.crypto.contains(code),
      let text = result.amount, let value = ExactAmount.parse(text)
    {
      monetaryAmount = IntentCurrencyAmount(amount: value, currencyCode: code)
    }
  }
}

/// Concise system-result formatting and speech; raw quote metadata stays internal.
enum ConversionPresentation {
  static func row(_ result: ConversionResult, request: ConversionRequest) -> String {
    let destination = result.destination.code ?? String(localized: "Local currency")
    guard let text = result.amount, let value = ExactAmount.parse(text) else {
      return String(localized: "\(destination): unavailable")
    }
    let precision = CurrencyDisplay.fractionDigits(destination)
    let step = Decimal(sign: .plus, exponent: -precision, significand: 1)
    let amount =
      value > 0 && value < step
      ? String(localized: "Less than \(CurrencyDisplay.format(step, code: destination))")
      : CurrencyDisplay.format(value, code: destination)
    let displayed: String
    if request.amount == "1" {
      let formatter = NumberFormatter()
      formatter.locale = .current; formatter.numberStyle = .decimal
      formatter.usesSignificantDigits = true; formatter.maximumSignificantDigits = 8
      displayed = formatter.string(from: NSDecimalNumber(decimal: value)) ?? amount
    } else {
      displayed = amount
    }
    let unit =
      ["XAU", "XAG", "XPT", "XPD"].contains(destination) ? String(localized: " troy oz") : ""
    return "\(displayed) \(destination)\(unit)"
  }
  static func readable(_ result: ConversionResult, request: ConversionRequest) -> String {
    let input = CurrencyDisplay.inputAmount(request.amount)
    let output = row(result, request: request)
    let local = result.id == CurrencySelection.localID ? String(localized: " (Local)") : ""
    return "\(input) \(request.source) → \(output)\(local)"
  }
  static func status(_ evaluation: ConversionEvaluation, result: ConversionResult? = nil) -> String
  {
    if let result {
      switch result.availability {
      case .localUnavailable: return String(localized: "Local currency is unavailable")
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
  static func speech(_ evaluation: ConversionEvaluation) -> String {
    let input = CurrencyDisplay.inputAmount(evaluation.request.amount)
    let rows = evaluation.results.prefix(3).map { row($0, request: evaluation.request) }
      .joined(separator: ", ")
    let remaining = max(0, evaluation.results.count - 3)
    let unavailable = evaluation.results.filter { $0.amount == nil }.count
    var text = String(localized: "\(input) \(evaluation.request.source) converts to \(rows).")
    if remaining > 0 { text += " " + String(localized: "\(remaining) more results are available.") }
    if unavailable > 0 {
      text += " " + String(localized: "\(unavailable) destinations are unavailable.")
    }
    let status = status(evaluation)
    if !status.isEmpty { text += " " + status + "." }
    return text
  }
}
