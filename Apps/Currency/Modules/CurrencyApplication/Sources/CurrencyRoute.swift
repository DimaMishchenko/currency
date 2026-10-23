import Conversion
import Foundation

/// Versioned external navigation to the existing converter and currency details.
public enum CurrencyRoute: Equatable, Sendable {
  /// The application's content URL scheme.
  public static let scheme = "currency"
  /// Opens the existing converter.
  case converter
  case widget(UUID)
  /// Opens immutable widget amounts in an enlarged, scrollable app presentation.
  case widgetReadout(UUID)
  /// Opens supported currency content without changing the saved selection.
  case currency(String)

  /// Encodes existing application content in a versioned URL.
  public var url: URL? {
    var components = URLComponents()
    components.scheme = Self.scheme
    components.queryItems = [URLQueryItem(name: "v", value: "1")]
    switch self {
    case .converter: components.host = "converter"
    case .widget(let id), .widgetReadout(let id):
      components.host = if case .widgetReadout = self { "widget-readout" } else { "widget" }
      components.queryItems?.append(URLQueryItem(name: "context", value: id.uuidString))
    case .currency(let id):
      components.host = "currency"
      components.queryItems?.append(URLQueryItem(name: "id", value: id))
    }
    return components.url
  }

  /// Rejects unknown versions, oversized URLs and unsupported currency identities.
  public init?(url: URL) {
    if url.absoluteString == "currency://convert" { self = .converter; return }
    guard url.absoluteString.count <= 65536,
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == Self.scheme, parts.path.isEmpty, parts.user == nil, parts.password == nil,
      parts.port == nil, parts.fragment == nil,
      let items = parts.queryItems,
      items.filter({ $0.name == "v" && $0.value == "1" }).count == 1
    else { return nil }
    switch parts.host {
    case "widget", "widget-readout":
      guard items.count == 2, let value = items.first(where: { $0.name == "context" })?.value,
        let id = UUID(uuidString: value)
      else { return nil }
      self = parts.host == "widget-readout" ? .widgetReadout(id) : .widget(id)
    case "converter":
      guard items.count == 1 else { return nil }
      self = .converter
    case "currency":
      guard items.count == 2, let id = items.first(where: { $0.name == "id" })?.value,
        id == CurrencySelection.localID || ConversionDestination(code: id).isValid
      else { return nil }
      self = .currency(id)
    default: return nil
    }
  }
}
