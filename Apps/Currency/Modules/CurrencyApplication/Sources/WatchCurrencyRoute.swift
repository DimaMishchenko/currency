import Conversion
import ExchangeRates
import Foundation

/// Validated external navigation shared by the Watch executable and its launchers.
public enum WatchCurrencyRoute: Equatable, Sendable {
  /// Opens the converter without replacing local input.
  case converter
  /// Opens the converter with an explicitly requested pair and optional amount.
  case convert(source: String, quote: String, amount: String?, metalUnit: MetalUnit? = nil)
  /// Opens history and rate provenance without changing converter input.
  case details(source: String, quote: String)

  /// Rejects unknown paths, duplicate parameters, unsupported assets and invalid amounts.
  public init?(url: URL) {
    guard url.absoluteString.count <= 4096,
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "currency-watch", parts.path.isEmpty, parts.user == nil,
      parts.password == nil, parts.port == nil, parts.fragment == nil
    else { return nil }
    let items = parts.queryItems ?? []
    guard Set(items.map(\.name)).count == items.count else { return nil }
    if parts.host == "convert", items.isEmpty { self = .converter; return }
    guard let source = items.first(where: { $0.name == "source" })?.value,
      let quote = items.first(where: { $0.name == "quote" })?.value,
      CurrencyCode(rawValue: source) != nil, CurrencyCode(rawValue: quote) != nil,
      source != quote
    else { return nil }
    switch parts.host {
    case "details":
      guard items.count == 2 else { return nil }
      self = .details(source: source, quote: quote)
    case "convert":
      guard items.allSatisfy({ ["source", "quote", "amount", "metalUnit"].contains($0.name) })
      else {
        return nil
      }
      let amountItem = items.first { $0.name == "amount" }
      var amount: String?
      if let amountItem {
        guard let text = amountItem.value, let value = ExactAmount.parse(text) else {
          return nil
        }
        amount = ExactAmount.string(value)
      }
      var metalUnit: MetalUnit?
      if let item = items.first(where: { $0.name == "metalUnit" }) {
        guard amount != nil, CurrencyCode(rawValue: source)?.isMetal == true,
          let text = item.value, let unit = MetalUnit(rawValue: text)
        else { return nil }
        metalUnit = unit
      }
      self = .convert(source: source, quote: quote, amount: amount, metalUnit: metalUnit)
    default: return nil
    }
  }
}
