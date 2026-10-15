import Foundation

struct FrankfurterRow: Decodable {
  let date: String
  let base: String
  let quote: String
  let rate: Decimal
}

/// A provider backed by the Frankfurter reference-rate API.
public struct FrankfurterProvider: RateProvider {
  static let allowedProviders =
    "AMCM,BAM,BANREP,BCB,BCBO,BCC,BCCH,BCP,BCRA,BCT,BDI,BDP,BI,BIS,BNA,BNM,BNR,BOA,BOC,BOJA,BOM,BOT,BOTA,BOZ,BRB,CBA,CBAR,CBC,CBG,CBI,CBK,CBLLR,CBM,CBS,CBSL,CBU,DAB,DNB,ECB,HMRC,HNB,INFOREURO,JPC,LB,MAS,MMA,MNB,NBC,NBE,NBG,NBK,NBKR,NBM,NBP,NBRB,NBRM,NBT,NRB,NRBT,RB,RBF,RBM,RBV,SARB,SBI,UST"
  let client: any HTTPClient
  /// Creates a Frankfurter provider.
  public init(client: any HTTPClient = NetworkClient()) { self.client = client }
  /// Fetches current Frankfurter reference rates.
  public func fetch() async throws -> [String: ExchangeRate] {
    guard
      let url = URL(
        string: "https://api.frankfurter.dev/v2/rates?base=EUR&providers=\(Self.allowedProviders)")
    else {
      throw RateError.invalidData
    }
    return try Self.decode(await client.get(url))
  }

  /// Decodes Frankfurter rows into normalized quotes.
  static func decode(_ data: Data) throws -> [String: ExchangeRate] {
    let rows = try JSONDecoder().decode([FrankfurterRow].self, from: data)
    guard !rows.isEmpty else { throw RateError.invalidData }
    var result: [String: ExchangeRate] = [:]
    for row in rows {
      guard row.base == "EUR", validDate(row.date), row.rate > 0, !row.rate.isNaN else {
        throw RateError.invalidData
      }
      guard CurrencyCatalog.codes.contains(row.quote), !CurrencyCatalog.crypto.contains(row.quote)
      else {
        continue
      }
      if row.date >= (result[row.quote]?.published ?? "") {
        result[row.quote] = ExchangeRate(
          row.rate, published: row.date,
          source: .init(provider: .frankfurter, observation: .dailyRate))
      }
    }
    guard let day = result["USD"]?.published else { throw RateError.invalidData }
    result["EUR"] = ExchangeRate(
      1, published: day, source: .init(provider: .frankfurter, observation: .dailyRate))
    if let sterling = result["GBP"] {
      for code in ["GGP", "IMP", "JEP"] {
        result[code] = ExchangeRate(
          sterling.value, published: sterling.published,
          source: RateSource(
            provider: .frankfurter, observation: .dailyRate,
            conversion: RateConversion(
              provider: .frankfurter, published: sterling.published,
              value: 1, base: "GBP", quote: code)))
      }
    }
    return result
  }
}
