import Foundation

struct FrankfurterRow: Decodable {
    let date: String
    let base: String
    let quote: String
    let rate: Decimal
}
public struct FrankfurterProvider: RateProvider {
    let client: any HTTPClient
    public init(client: any HTTPClient = NetworkClient()) { self.client = client }
    public func fetch() async throws -> [String: Quote] {
        try Self.decode(await client.get(URL(string: "https://api.frankfurter.dev/v2/rates?base=EUR")!))
    }
    public static func decode(_ data: Data) throws -> [String: Quote] {
        let rows = try JSONDecoder().decode([FrankfurterRow].self, from: data)
        guard !rows.isEmpty else { throw RateError.invalidData }
        var result: [String: Quote] = [:]
        for row in rows {
            guard row.base == "EUR", validDate(row.date), row.rate > 0, !row.rate.isNaN else { throw RateError.invalidData }
            guard Currency.codes.contains(row.quote), !Currency.crypto.contains(row.quote) else { continue }
            if row.date >= (result[row.quote]?.published ?? "") { result[row.quote] = Quote(row.rate, published: row.date, source: "Frankfurter") }
        }
        guard let day = result["USD"]?.published else { throw RateError.invalidData }
        result["EUR"] = Quote(1, published: day, source: "Frankfurter")
        return result
    }
}
public struct FiatProvider: RateProvider {
    let primary: any RateProvider
    let fallback: any RateProvider
    public init(primary: any RateProvider = FrankfurterProvider(), fallback: any RateProvider = ECBProvider()) { self.primary = primary; self.fallback = fallback }
    public func fetch() async throws -> [String: Quote] {
        do { return try await primary.fetch() }
        catch { try Task.checkCancellation(); return try await fallback.fetch() }
    }
}
public struct CoinbaseProvider: RateProvider {
    let client: any HTTPClient
    public init(client: any HTTPClient = NetworkClient()) { self.client = client }
    public func fetch() async throws -> [String: Quote] {
        var result: [String: Quote] = [:]
        for code in Currency.crypto.sorted() {
            do {
                let data = try await client.get(URL(string: "https://api.exchange.coinbase.com/products/\(code)-EUR/ticker")!)
                result[code] = try Self.decode(data)
            } catch { try Task.checkCancellation() }
            // Public limit is 10 requests/second per IP. Pace even fast cached replies.
            try await Task.sleep(for: .milliseconds(150))
        }
        guard !result.isEmpty else { throw RateError.unavailable }
        return result
    }
    public static func decode(_ data: Data, now: Date = .now) throws -> Quote {
        struct Ticker: Decodable { let price: String; let time: String }
        let ticker = try JSONDecoder().decode(Ticker.self, from: data)
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = parser.date(from: ticker.time)
        parser.formatOptions = [.withInternetDateTime]
        guard let time = fractional ?? parser.date(from: ticker.time), now.timeIntervalSince(time) >= -60, now.timeIntervalSince(time) < 3600,
              let price = Decimal(string: ticker.price, locale: Locale(identifier: "en_US_POSIX")), price > 0, !price.isNaN else { throw RateError.invalidData }
        // Ticker is EUR per coin; RateBook stores coins per EUR.
        return Quote(1 / price, published: String(ticker.time.prefix(10)), source: "Coinbase", observedAt: time)
    }
}
