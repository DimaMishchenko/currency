import Conversion
import Foundation

/// Versioned external navigation to existing selected-currency details.
public enum CurrencyRoute: Equatable, Sendable {
  /// Opens currently selected currency content.
  case currency(String)

  /// Encodes the selected currency identity in a versioned content URL.
  public var url: URL? {
    var components = URLComponents()
    components.scheme = "currency"
    components.queryItems = [URLQueryItem(name: "v", value: "1")]
    switch self {
    case .currency(let id):
      components.host = "currency"
      components.queryItems?.append(URLQueryItem(name: "id", value: id))
    }
    return components.url
  }

  /// Rejects unknown versions, oversized URLs and unsupported currency identities.
  public init?(url: URL) {
    guard url.absoluteString.count <= 65536,
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "currency", parts.path.isEmpty, parts.user == nil, parts.password == nil,
      parts.port == nil, parts.fragment == nil,
      let items = parts.queryItems, items.count == 2,
      items.filter({ $0.name == "v" && $0.value == "1" }).count == 1
    else { return nil }
    switch parts.host {
    case "currency":
      guard let id = items.first(where: { $0.name == "id" })?.value,
        id == CurrencySelection.localID || ConversionDestination(code: id).isValid
      else { return nil }
      self = .currency(id)
    default: return nil
    }
  }
}
