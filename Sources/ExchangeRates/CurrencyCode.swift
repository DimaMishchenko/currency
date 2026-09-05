import Foundation

/// A currency supported by the bundled catalog, encoded using its uppercase provider code.
/// Unknown provider codes can still be represented by the string-based rate APIs.
public enum CurrencyCode: String, Codable, CaseIterable, Sendable {
  /// The EUR currency or asset code.
  case eur = "EUR"
  /// The USD currency or asset code.
  case usd = "USD"
  /// The GBP currency or asset code.
  case gbp = "GBP"
  /// The CZK currency or asset code.
  case czk = "CZK"
  /// The CHF currency or asset code.
  case chf = "CHF"
  /// The JPY currency or asset code.
  case jpy = "JPY"
  /// The AED currency or asset code.
  case aed = "AED"
  /// The AFN currency or asset code.
  case afn = "AFN"
  /// The ALL currency or asset code.
  case all = "ALL"
  /// The AMD currency or asset code.
  case amd = "AMD"
  /// The ANG currency or asset code.
  case ang = "ANG"
  /// The AOA currency or asset code.
  case aoa = "AOA"
  /// The ARS currency or asset code.
  case ars = "ARS"
  /// The AUD currency or asset code.
  case aud = "AUD"
  /// The AWG currency or asset code.
  case awg = "AWG"
  /// The AZN currency or asset code.
  case azn = "AZN"
  /// The BAM currency or asset code.
  case bam = "BAM"
  /// The BBD currency or asset code.
  case bbd = "BBD"
  /// The BDT currency or asset code.
  case bdt = "BDT"
  /// The BHD currency or asset code.
  case bhd = "BHD"
  /// The BIF currency or asset code.
  case bif = "BIF"
  /// The BMD currency or asset code.
  case bmd = "BMD"
  /// The BND currency or asset code.
  case bnd = "BND"
  /// The BOB currency or asset code.
  case bob = "BOB"
  /// The BRL currency or asset code.
  case brl = "BRL"
  /// The BSD currency or asset code.
  case bsd = "BSD"
  /// The BTN currency or asset code.
  case btn = "BTN"
  /// The BWP currency or asset code.
  case bwp = "BWP"
  /// The BYN currency or asset code.
  case byn = "BYN"
  /// The BZD currency or asset code.
  case bzd = "BZD"
  /// The CAD currency or asset code.
  case cad = "CAD"
  /// The CDF currency or asset code.
  case cdf = "CDF"
  /// The CLP currency or asset code.
  case clp = "CLP"
  /// The CNH currency or asset code.
  case cnh = "CNH"
  /// The CNY currency or asset code.
  case cny = "CNY"
  /// The COP currency or asset code.
  case cop = "COP"
  /// The CRC currency or asset code.
  case crc = "CRC"
  /// The CUP currency or asset code.
  case cup = "CUP"
  /// The CVE currency or asset code.
  case cve = "CVE"
  /// The DJF currency or asset code.
  case djf = "DJF"
  /// The DKK currency or asset code.
  case dkk = "DKK"
  /// The DOP currency or asset code.
  case dop = "DOP"
  /// The DZD currency or asset code.
  case dzd = "DZD"
  /// The EGP currency or asset code.
  case egp = "EGP"
  /// The ERN currency or asset code.
  case ern = "ERN"
  /// The ETB currency or asset code.
  case etb = "ETB"
  /// The FJD currency or asset code.
  case fjd = "FJD"
  /// The FKP currency or asset code.
  case fkp = "FKP"
  /// The GEL currency or asset code.
  case gel = "GEL"
  /// The GGP currency or asset code.
  case ggp = "GGP"
  /// The GHS currency or asset code.
  case ghs = "GHS"
  /// The GIP currency or asset code.
  case gip = "GIP"
  /// The GMD currency or asset code.
  case gmd = "GMD"
  /// The GNF currency or asset code.
  case gnf = "GNF"
  /// The GTQ currency or asset code.
  case gtq = "GTQ"
  /// The GYD currency or asset code.
  case gyd = "GYD"
  /// The HKD currency or asset code.
  case hkd = "HKD"
  /// The HNL currency or asset code.
  case hnl = "HNL"
  /// The HTG currency or asset code.
  case htg = "HTG"
  /// The HUF currency or asset code.
  case huf = "HUF"
  /// The IDR currency or asset code.
  case idr = "IDR"
  /// The ILS currency or asset code.
  case ils = "ILS"
  /// The IMP currency or asset code.
  case imp = "IMP"
  /// The INR currency or asset code.
  case inr = "INR"
  /// The IQD currency or asset code.
  case iqd = "IQD"
  /// The IRR currency or asset code.
  case irr = "IRR"
  /// The ISK currency or asset code.
  case isk = "ISK"
  /// The JEP currency or asset code.
  case jep = "JEP"
  /// The JMD currency or asset code.
  case jmd = "JMD"
  /// The JOD currency or asset code.
  case jod = "JOD"
  /// The KES currency or asset code.
  case kes = "KES"
  /// The KGS currency or asset code.
  case kgs = "KGS"
  /// The KHR currency or asset code.
  case khr = "KHR"
  /// The KMF currency or asset code.
  case kmf = "KMF"
  /// The KPW currency or asset code.
  case kpw = "KPW"
  /// The KRW currency or asset code.
  case krw = "KRW"
  /// The KWD currency or asset code.
  case kwd = "KWD"
  /// The KYD currency or asset code.
  case kyd = "KYD"
  /// The KZT currency or asset code.
  case kzt = "KZT"
  /// The LAK currency or asset code.
  case lak = "LAK"
  /// The LBP currency or asset code.
  case lbp = "LBP"
  /// The LKR currency or asset code.
  case lkr = "LKR"
  /// The LRD currency or asset code.
  case lrd = "LRD"
  /// The LSL currency or asset code.
  case lsl = "LSL"
  /// The LYD currency or asset code.
  case lyd = "LYD"
  /// The MAD currency or asset code.
  case mad = "MAD"
  /// The MDL currency or asset code.
  case mdl = "MDL"
  /// The MGA currency or asset code.
  case mga = "MGA"
  /// The MKD currency or asset code.
  case mkd = "MKD"
  /// The MMK currency or asset code.
  case mmk = "MMK"
  /// The MNT currency or asset code.
  case mnt = "MNT"
  /// The MOP currency or asset code.
  case mop = "MOP"
  /// The MRO currency or asset code.
  case mro = "MRO"
  /// The MRU currency or asset code.
  case mru = "MRU"
  /// The MUR currency or asset code.
  case mur = "MUR"
  /// The MVR currency or asset code.
  case mvr = "MVR"
  /// The MWK currency or asset code.
  case mwk = "MWK"
  /// The MXN currency or asset code.
  case mxn = "MXN"
  /// The MYR currency or asset code.
  case myr = "MYR"
  /// The MZN currency or asset code.
  case mzn = "MZN"
  /// The NAD currency or asset code.
  case nad = "NAD"
  /// The NGN currency or asset code.
  case ngn = "NGN"
  /// The NIO currency or asset code.
  case nio = "NIO"
  /// The NOK currency or asset code.
  case nok = "NOK"
  /// The NPR currency or asset code.
  case npr = "NPR"
  /// The NZD currency or asset code.
  case nzd = "NZD"
  /// The OMR currency or asset code.
  case omr = "OMR"
  /// The PAB currency or asset code.
  case pab = "PAB"
  /// The PEN currency or asset code.
  case pen = "PEN"
  /// The PGK currency or asset code.
  case pgk = "PGK"
  /// The PHP currency or asset code.
  case php = "PHP"
  /// The PKR currency or asset code.
  case pkr = "PKR"
  /// The PLN currency or asset code.
  case pln = "PLN"
  /// The PYG currency or asset code.
  case pyg = "PYG"
  /// The QAR currency or asset code.
  case qar = "QAR"
  /// The RON currency or asset code.
  case ron = "RON"
  /// The RSD currency or asset code.
  case rsd = "RSD"
  /// The RUB currency or asset code.
  case rub = "RUB"
  /// The RWF currency or asset code.
  case rwf = "RWF"
  /// The SAR currency or asset code.
  case sar = "SAR"
  /// The SBD currency or asset code.
  case sbd = "SBD"
  /// The SCR currency or asset code.
  case scr = "SCR"
  /// The SDG currency or asset code.
  case sdg = "SDG"
  /// The SEK currency or asset code.
  case sek = "SEK"
  /// The SGD currency or asset code.
  case sgd = "SGD"
  /// The SHP currency or asset code.
  case shp = "SHP"
  /// The SLE currency or asset code.
  case sle = "SLE"
  /// The SOS currency or asset code.
  case sos = "SOS"
  /// The SRD currency or asset code.
  case srd = "SRD"
  /// The SSP currency or asset code.
  case ssp = "SSP"
  /// The STN currency or asset code.
  case stn = "STN"
  /// The SVC currency or asset code.
  case svc = "SVC"
  /// The SYP currency or asset code.
  case syp = "SYP"
  /// The SZL currency or asset code.
  case szl = "SZL"
  /// The THB currency or asset code.
  case thb = "THB"
  /// The TJS currency or asset code.
  case tjs = "TJS"
  /// The TMT currency or asset code.
  case tmt = "TMT"
  /// The TND currency or asset code.
  case tnd = "TND"
  /// The TOP currency or asset code.
  case top = "TOP"
  /// The TRY currency or asset code.
  case `try` = "TRY"
  /// The TTD currency or asset code.
  case ttd = "TTD"
  /// The TWD currency or asset code.
  case twd = "TWD"
  /// The TZS currency or asset code.
  case tzs = "TZS"
  /// The UAH currency or asset code.
  case uah = "UAH"
  /// The UGX currency or asset code.
  case ugx = "UGX"
  /// The UYU currency or asset code.
  case uyu = "UYU"
  /// The UZS currency or asset code.
  case uzs = "UZS"
  /// The VES currency or asset code.
  case ves = "VES"
  /// The VND currency or asset code.
  case vnd = "VND"
  /// The VUV currency or asset code.
  case vuv = "VUV"
  /// The WST currency or asset code.
  case wst = "WST"
  /// The XAF currency or asset code.
  case xaf = "XAF"
  /// The XAG currency or asset code.
  case xag = "XAG"
  /// The XAU currency or asset code.
  case xau = "XAU"
  /// The XCD currency or asset code.
  case xcd = "XCD"
  /// The XCG currency or asset code.
  case xcg = "XCG"
  /// The XDR currency or asset code.
  case xdr = "XDR"
  /// The XOF currency or asset code.
  case xof = "XOF"
  /// The XPD currency or asset code.
  case xpd = "XPD"
  /// The XPF currency or asset code.
  case xpf = "XPF"
  /// The XPT currency or asset code.
  case xpt = "XPT"
  /// The YER currency or asset code.
  case yer = "YER"
  /// The ZAR currency or asset code.
  case zar = "ZAR"
  /// The ZMW currency or asset code.
  case zmw = "ZMW"
  /// The ZWG currency or asset code.
  case zwg = "ZWG"
  /// The BTC currency or asset code.
  case btc = "BTC"
  /// The ETH currency or asset code.
  case eth = "ETH"
  /// The SOL currency or asset code.
  case sol = "SOL"
  /// The DOGE currency or asset code.
  case doge = "DOGE"
  /// The LTC currency or asset code.
  case ltc = "LTC"
  /// The USDC currency or asset code.
  case usdc = "USDC"
  /// The USDT currency or asset code.
  case usdt = "USDT"

  /// The XRP asset code.
  case xrp = "XRP"
  /// The Cardano asset code.
  case ada = "ADA"
  /// The Avalanche asset code.
  case avax = "AVAX"
  /// The Chainlink asset code.
  case link = "LINK"
  /// The Polkadot asset code.
  case dot = "DOT"
  /// The Bitcoin Cash asset code.
  case bch = "BCH"
  /// The Stellar asset code.
  case xlm = "XLM"
  /// The Cosmos asset code.
  case atom = "ATOM"
  /// The Uniswap asset code.
  case uni = "UNI"
  /// The Ethereum Classic asset code.
  case etc = "ETC"
  /// The Filecoin asset code.
  case fil = "FIL"
  /// The Aave asset code.
  case aave = "AAVE"
  /// The Algorand asset code.
  case algo = "ALGO"
  /// The Shiba Inu asset code.
  case shib = "SHIB"
  /// The Internet Computer asset code.
  case icp = "ICP"

  /// Whether this asset uses the cryptocurrency rate and history providers.
  public var isCryptocurrency: Bool {
    switch self {
    case .btc, .eth, .sol, .doge, .ltc, .usdc, .usdt,
      .xrp, .ada, .avax, .link, .dot, .bch, .xlm, .atom,
      .uni, .etc, .fil, .aave, .algo, .shib, .icp: true
    default: false
    }
  }
}
