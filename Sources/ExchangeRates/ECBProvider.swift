import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif

/// A provider backed by the European Central Bank reference-rate feed.
public struct ECBProvider: RateProvider {
  let client: any HTTPClient
  /// Creates an ECB provider.
  public init(client: any HTTPClient = NetworkClient()) { self.client = client }
  /// Fetches and decodes the latest ECB reference rates.
  public func fetch() async throws -> [String: ExchangeRate] {
    guard
      let url = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")
    else { throw RateError.invalidData }
    return try Self.decode(await client.get(url))
  }
  /// Decodes ECB XML into normalized quotes.
  static func decode(_ data: Data) throws -> [String: ExchangeRate] {
    let delegate = ECBParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldResolveExternalEntities = false
    guard parser.parse(), validDate(delegate.date), !delegate.rates.isEmpty, !delegate.invalid
    else { throw RateError.invalidData }
    var result = delegate.rates.mapValues {
      ExchangeRate(
        $0, published: delegate.date, source: .init(provider: .ecb, observation: .dailyRate))
    }
    result["EUR"] = ExchangeRate(
      1, published: delegate.date, source: .init(provider: .ecb, observation: .dailyRate))
    return result
  }
}
private final class ECBParser: NSObject, XMLParserDelegate {
  var date = ""
  var rates: [String: Decimal] = [:]
  var invalid = false
  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    if let time = attributes["time"] { date = time }
    if let code = attributes["currency"] {
      guard let raw = attributes["rate"],
        let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), value > 0,
        !value.isNaN
      else {
        invalid = true
        return
      }
      rates[code] = value
    }
  }
}
