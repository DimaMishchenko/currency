import Foundation

extension HistoryService {
  static func usesFiatHistory(base: String, quote: String) -> Bool {
    !CurrencyCatalog.crypto.contains(base) && !CurrencyCatalog.crypto.contains(quote)
      && !CurrencyCatalog.metals.contains(base) && !CurrencyCatalog.metals.contains(quote)
  }

  static func fetchFiatHistory(
    client: any HTTPClient, base: String, quote: String, start: Date, now: Date
  ) async throws -> [HistoryPoint] {
    func canonical(_ code: String) -> String {
      ["GGP", "IMP", "JEP"].contains(code) ? "GBP" : code
    }
    let base = canonical(base)
    let quote = canonical(quote)
    let codes = Set([base, quote]).subtracting(["EUR"]).sorted()
    let from = String(start.ISO8601Format().prefix(10))
    let through = String(now.ISO8601Format().prefix(10))
    for provider in ["ECB", "CBU"] {
      try Task.checkCancellation()
      do {
        guard var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates")
        else { throw RateError.invalidData }
        components.queryItems = [
          URLQueryItem(name: "base", value: "EUR"),
          URLQueryItem(name: "quotes", value: codes.joined(separator: ",")),
          URLQueryItem(name: "from", value: from),
          URLQueryItem(name: "to", value: through),
          URLQueryItem(name: "providers", value: provider)
        ]
        guard let url = components.url else { throw RateError.invalidData }
        let rows = try JSONDecoder().decode([FrankfurterRow].self, from: await client.get(url))
        let formatter = ISO8601DateFormatter()
        var observations: [Date: [String: Double]] = [:]
        for row in rows {
          guard row.base == "EUR", codes.contains(row.quote),
            validDate(row.date), row.date >= from, row.date <= through,
            row.rate > 0, !row.rate.isNaN,
            let date = formatter.date(from: "\(row.date)T00:00:00Z")
          else { throw RateError.invalidData }
          let value = NSDecimalNumber(decimal: row.rate).doubleValue
          guard value.isFinite, value > 0, observations[date]?[row.quote] == nil else {
            throw RateError.invalidData
          }
          observations[date, default: [:]][row.quote] = value
        }
        let points =
          try observations.compactMap { date, values -> HistoryPoint? in
            let a = base == "EUR" ? 1 : values[base]
            let b = quote == "EUR" ? 1 : values[quote]
            guard let a, let b else { return nil }
            let value = b / a
            guard value.isFinite, value > 0 else { throw RateError.invalidData }
            return HistoryPoint(date: date, value: value)
          }
          .sorted { $0.date < $1.date }
        guard points.count >= 2 else { throw RateError.unavailable }
        return points
      } catch {
        try Task.checkCancellation()
      }
    }
    throw RateError.unavailable
  }
}
