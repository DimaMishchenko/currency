import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct Quote: Codable, Sendable, Equatable {
    public let value: Decimal
    public let published: String
    public let source: String
    public let observedAt: Date?
    public init(_ value: Decimal, published: String, source: String, observedAt: Date? = nil) {
        self.value = value; self.published = published; self.source = source; self.observedAt = observedAt
    }
}

public struct RateBook: Codable, Sendable {
    public var quotes: [String: Quote]
    public var fetchedAt: Date
    public var dailyQuotes: [String: Quote]?
    public var dailyFetchedAt: Date?
    public var checkedAt: Date?
    public init(quotes: [String: Quote] = [:], fetchedAt: Date = .distantPast, dailyQuotes: [String: Quote]? = nil, dailyFetchedAt: Date? = nil, checkedAt: Date? = nil) {
        self.quotes = quotes; self.fetchedAt = fetchedAt; self.dailyQuotes = dailyQuotes; self.dailyFetchedAt = dailyFetchedAt; self.checkedAt = checkedAt
    }
    public func convert(_ amount: Decimal, from: String, to: String) -> Decimal? {
        if from == to { return amount }
        guard let a = quotes[from]?.value, let b = quotes[to]?.value, a > 0, b > 0 else { return nil }
        return amount / a * b
    }
    public func details(from: String, to: String) -> String {
        let rows = [quotes[from], quotes[to]].compactMap { $0 }.map { "\($0.source) · \($0.published)" }
        return Array(Set(rows)).sorted().joined(separator: " / ")
    }
}

public enum RateError: Error { case invalidData, http(Int), unavailable }
public protocol HTTPClient: Sendable { func get(_ url: URL) async throws -> Data }
public struct NetworkClient: HTTPClient {
    private let timeout: TimeInterval
    public init(timeout: TimeInterval = 12) { self.timeout = timeout }
    public func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RateError.invalidData }
        guard (200..<300).contains(response.statusCode) else { throw RateError.http(response.statusCode) }
        return data
    }
}
public protocol RateProvider: Sendable { func fetch() async throws -> [String: Quote] }
public struct ECBProvider: RateProvider {
    let client: any HTTPClient
    public init(client: any HTTPClient = NetworkClient()) { self.client = client }
    public func fetch() async throws -> [String: Quote] {
        try Self.decode(await client.get(URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!))
    }
    public static func decode(_ data: Data) throws -> [String: Quote] {
        let delegate = ECBParser(); let parser = XMLParser(data: data)
        parser.delegate = delegate; parser.shouldResolveExternalEntities = false
        guard parser.parse(), validDate(delegate.date), !delegate.rates.isEmpty, !delegate.invalid else { throw RateError.invalidData }
        var result = delegate.rates.mapValues { Quote($0, published: delegate.date, source: "ECB") }
        result["EUR"] = Quote(1, published: delegate.date, source: "ECB")
        return result
    }
}
private final class ECBParser: NSObject, XMLParserDelegate {
    var date = ""; var rates: [String: Decimal] = [:]; var invalid = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if let time = attributes["time"] { date = time }
        if let code = attributes["currency"] {
            guard let raw = attributes["rate"], let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), value > 0, !value.isNaN else { invalid = true; return }
            rates[code] = value
        }
    }
}
func validDate(_ value: String) -> Bool {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
    guard let date = formatter.date(from: value) else { return false }
    return formatter.string(from: date) == value && date < Date().addingTimeInterval(86400)
}
public struct FawazProvider: RateProvider {
    let client: any HTTPClient
    public init(client: any HTTPClient = NetworkClient()) { self.client = client }
    public func fetch() async throws -> [String: Quote] {
        for endpoint in ["https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/eur.min.json", "https://latest.currency-api.pages.dev/v1/currencies/eur.min.json"] {
            do { return try Self.decode(await client.get(URL(string: endpoint)!)) }
            catch { try Task.checkCancellation() }
        }
        throw RateError.unavailable
    }
    public static func decode(_ data: Data) throws -> [String: Quote] {
        struct Payload: Decodable { let date: String; let eur: [String: Decimal] }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard validDate(payload.date), payload.eur["usd"] != nil, payload.eur["btc"] != nil else { throw RateError.invalidData }
        var result: [String: Quote] = [:]
        for (code, value) in payload.eur where Currency.codes.contains(code.uppercased()) {
            guard value > 0, !value.isNaN else { throw RateError.invalidData }
            result[code.uppercased()] = Quote(value, published: payload.date, source: "Fawaz · daily")
        }
        result["EUR"] = Quote(1, published: payload.date, source: "Fawaz · daily")
        return result
    }
}
public enum Currency {
    public static let crypto: Set<String> = ["BTC", "ETH", "SOL", "DOGE", "LTC", "USDC", "USDT"]
    // Frankfurter v2 current-currency catalog, bundled for offline selection (2026-09-05).
    public static let codes = ["EUR", "USD", "GBP", "CZK", "CHF", "JPY"] + "AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BHD BIF BMD BND BOB BRL BSD BTN BWP BYN BZD CAD CDF CLP CNH CNY COP CRC CUP CVE DJF DKK DOP DZD EGP ERN ETB FJD FKP GEL GGP GHS GIP GMD GNF GTQ GYD HKD HNL HTG HUF IDR ILS IMP INR IQD IRR ISK JEP JMD JOD KES KGS KHR KMF KPW KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK MNT MOP MRO MRU MUR MVR MWK MXN MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG QAR RON RSD RUB RWF SAR SBD SCR SDG SEK SGD SHP SLE SOS SRD SSP STN SVC SYP SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX UYU UZS VES VND VUV WST XAF XAG XAU XCD XCG XDR XOF XPD XPF XPT YER ZAR ZMW ZWG BTC ETH SOL DOGE LTC USDC USDT".split(separator: " ").map(String.init)
    public static func name(_ code: String) -> String {
        ["BTC": "Bitcoin", "ETH": "Ethereum", "SOL": "Solana", "DOGE": "Dogecoin", "LTC": "Litecoin", "USDC": "USD Coin", "USDT": "Tether"][code] ?? Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
    public static func format(_ value: Decimal?, code: String) -> String {
        guard let value, !value.isNaN else { return "—" }
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = fractionDigits(code)
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }
}

public struct RefreshResult: Sendable { public let book: RateBook; public let warning: String? }
public actor RateService {
    private let fiat: any RateProvider; private let daily: any RateProvider; private let crypto: (any RateProvider)?
    public init(fiat: any RateProvider = FiatProvider(), daily: any RateProvider = FawazProvider(), crypto: (any RateProvider)? = CoinbaseProvider()) { self.fiat = fiat; self.daily = daily; self.crypto = crypto }
    public func refresh(previous: RateBook, force: Bool = false) async -> RefreshResult {
        let refreshDaily = force || Date().timeIntervalSince(previous.dailyFetchedAt ?? .distantPast) >= 21600
        async let fiatResult = refreshDaily ? fetch(fiat) : nil
        async let dailyResult = refreshDaily ? fetch(daily) : nil
        async let cryptoResult = fetch(crypto)
        let (ecb, fawaz) = await (fiatResult, dailyResult)
        var quotes = previous.dailyQuotes ?? previous.quotes.filter { $0.value.observedAt == nil }
        // Each quote retains its own publication date; never replace newer cache data with older data.
        for incoming in [fawaz, ecb] {
            for (code, quote) in incoming ?? [:] {
                if quote.published >= (quotes[code]?.published ?? "") { quotes[code] = quote }
            }
        }
        let dailyQuotes = quotes
        let live = await cryptoResult
        for (code, quote) in live ?? [:] where Currency.crypto.contains(code) { quotes[code] = quote }
        // Never leave an old intraday quote masquerading as current after Coinbase fails.
        let success = ecb != nil || fawaz != nil || live != nil
        let warning: String? = refreshDaily && ecb == nil && fawaz == nil ? "Can’t update daily rates. Showing saved rates." : crypto != nil && live?.count != Currency.crypto.count ? "Some crypto rates use the daily fallback." : nil
        return RefreshResult(book: RateBook(quotes: quotes, fetchedAt: success ? Date() : previous.fetchedAt, dailyQuotes: dailyQuotes, dailyFetchedAt: ecb != nil && fawaz != nil ? Date() : previous.dailyFetchedAt, checkedAt: Date()), warning: warning)
    }
    private func fetch(_ provider: (any RateProvider)?) async -> [String: Quote]? { guard let provider else { return nil }; return try? await provider.fetch() }
}
