import Foundation

struct BundledHistory: Decodable {
  let version: Int
  let crypto: [String: [[Double]]]
  let cryptoFX: [String: [[Double]]]
  let fiat: [String: [[Double]]]
  let fawaz: [String: [[Double]]]

  static let archive: BundledHistory? = {
    guard let url = Bundle.module.url(forResource: "history-monthly-v1", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let archive = try? JSONDecoder().decode(BundledHistory.self, from: data), archive.version == 1
    else { return nil }
    return archive
  }()

  static func points(base: String, quote: String, through now: Date) throws -> [HistoryPoint] {
    guard let archive else { return [] }
    let baseCrypto = CurrencyCatalog.crypto.contains(base)
    let quoteCrypto = CurrencyCatalog.crypto.contains(quote)
    let requiresFX = baseCrypto != quoteCrypto && base != "USD" && quote != "USD"
    func values(_ code: String, crypto: Bool) -> [Date: Double] {
      let canonical = ["GGP", "IMP", "JEP"].contains(code) ? "GBP" : code
      if canonical == "USD" && baseCrypto != quoteCrypto {
        let other = baseCrypto ? base : quote
        let rows = requiresFX ? archive.cryptoFX[other] : archive.crypto[other]
        return Dictionary(
          (rows ?? [])
            .compactMap { row in
              guard row.count == 2, row[0] * 86400 <= now.timeIntervalSince1970 else { return nil }
              return (Date(timeIntervalSince1970: row[0] * 86400), 1.0)
            }, uniquingKeysWith: { _, last in last })
      }
      let rows =
        crypto
        ? (requiresFX ? archive.cryptoFX[canonical] : archive.crypto[canonical])
        : archive.fiat[canonical]
      return Dictionary(
        (rows ?? [])
          .compactMap { row -> (Date, Double)? in
            guard row.count == 2, row[0].isFinite, row[1].isFinite, row[1] > 0 else { return nil }
            let date = Date(timeIntervalSince1970: row[0] * 86400)
            guard date <= now else { return nil }
            return (date, crypto ? row[1] : 1 / row[1])
          }, uniquingKeysWith: { _, latest in latest })
    }
    let numerator = values(base, crypto: baseCrypto)
    let denominator = values(quote, crypto: quoteCrypto)
    return
      try numerator.compactMap { date, value in
        guard let divisor = denominator[date] else { return nil }
        let result = value / divisor
        guard result.isFinite && result > 0 else { throw RateError.invalidData }
        return HistoryPoint(date: date, value: result)
      }
      .sorted { $0.date < $1.date }
  }
  static func recentPoints(base: String, quote: String, through now: Date) -> [HistoryPoint] {
    guard let archive else { return [] }
    func values(_ code: String) -> [Double: Double] {
      let canonical = ["GGP", "IMP", "JEP"].contains(code) ? "GBP" : code
      return Dictionary(
        (archive.fawaz[canonical] ?? [])
          .compactMap { row in
            guard row.count == 2, row[0].isFinite, row[1].isFinite, row[1] > 0,
              row[0] * 86400 <= now.timeIntervalSince1970
            else { return nil }
            return (row[0], row[1])
          }, uniquingKeysWith: { _, last in last })
    }
    let quotes = values(quote)
    return values(base)
      .compactMap { day, baseValue in
        guard let quoteValue = quotes[day] else { return nil }
        let value = quoteValue / baseValue
        guard value.isFinite && value > 0 else { return nil }
        return HistoryPoint(date: Date(timeIntervalSince1970: day * 86400), value: value)
      }
      .sorted { $0.date < $1.date }
  }

}
