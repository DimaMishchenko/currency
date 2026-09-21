import AppIntents
import Widgets

// App Intents keeps a concrete, statically discoverable catalog in the extension.
enum CurrencySymbolChoice: String, AppEnum {
  case austral = "australsign"
  case australiandollar = "australiandollarsign"
  case baht = "bahtsign"
  case bitcoin = "bitcoinsign"
  case brazilianreal = "brazilianrealsign"
  case cedi = "cedisign"
  case cent = "centsign"
  case chineseyuanrenminbi = "chineseyuanrenminbisign"
  case coloncurrency = "coloncurrencysign"
  case cruzeiro = "cruzeirosign"
  case danishkrone = "danishkronesign"
  case dong = "dongsign"
  case dollar = "dollarsign"
  case euro = "eurosign"
  case eurozone = "eurozonesign"
  case florin = "florinsign"
  case franc = "francsign"
  case guarani = "guaranisign"
  case hryvnia = "hryvniasign"
  case indianrupee = "indianrupeesign"
  case kip = "kipsign"
  case lari = "larisign"
  case lira = "lirasign"
  case malaysianringgit = "malaysianringgitsign"
  case manat = "manatsign"
  case mill = "millsign"
  case naira = "nairasign"
  case norwegiankrone = "norwegiankronesign"
  case peruviansoles = "peruviansolessign"
  case peseta = "pesetasign"
  case peso = "pesosign"
  case polishzloty = "polishzlotysign"
  case ruble = "rublesign"
  case rupee = "rupeesign"
  case shekel = "shekelsign"
  case singaporedollar = "singaporedollarsign"
  case sterling = "sterlingsign"
  case swedishkrona = "swedishkronasign"
  case tenge = "tengesign"
  case tugrik = "tugriksign"
  case turkishlira = "turkishlirasign"
  case won = "wonsign"
  case yen = "yensign"
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Currency symbol"
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .austral: .init(title: "Austral", image: .init(systemName: "australsign")),
    .australiandollar: .init(
      title: "Australian dollar", image: .init(systemName: "australiandollarsign")),
    .baht: .init(title: "Thai baht", image: .init(systemName: "bahtsign")),
    .bitcoin: .init(title: "Bitcoin", image: .init(systemName: "bitcoinsign")),
    .brazilianreal: .init(title: "Brazilian real", image: .init(systemName: "brazilianrealsign")),
    .cedi: .init(title: "Ghanaian cedi", image: .init(systemName: "cedisign")),
    .cent: .init(title: "Cent", image: .init(systemName: "centsign")),
    .chineseyuanrenminbi: .init(
      title: "Chinese yuan", image: .init(systemName: "chineseyuanrenminbisign")),
    .coloncurrency: .init(title: "Colón", image: .init(systemName: "coloncurrencysign")),
    .cruzeiro: .init(title: "Cruzeiro", image: .init(systemName: "cruzeirosign")),
    .danishkrone: .init(title: "Danish krone", image: .init(systemName: "danishkronesign")),
    .dong: .init(title: "Vietnamese dong", image: .init(systemName: "dongsign")),
    .dollar: .init(title: "Dollar", image: .init(systemName: "dollarsign")),
    .euro: .init(title: "Euro", image: .init(systemName: "eurosign")),
    .eurozone: .init(title: "Eurozone", image: .init(systemName: "eurozonesign")),
    .florin: .init(title: "Florin", image: .init(systemName: "florinsign")),
    .franc: .init(title: "Franc", image: .init(systemName: "francsign")),
    .guarani: .init(title: "Guaraní", image: .init(systemName: "guaranisign")),
    .hryvnia: .init(title: "Ukrainian hryvnia", image: .init(systemName: "hryvniasign")),
    .indianrupee: .init(title: "Indian rupee", image: .init(systemName: "indianrupeesign")),
    .kip: .init(title: "Lao kip", image: .init(systemName: "kipsign")),
    .lari: .init(title: "Georgian lari", image: .init(systemName: "larisign")),
    .lira: .init(title: "Lira", image: .init(systemName: "lirasign")),
    .malaysianringgit: .init(
      title: "Malaysian ringgit", image: .init(systemName: "malaysianringgitsign")),
    .manat: .init(title: "Manat", image: .init(systemName: "manatsign")),
    .mill: .init(title: "Mill", image: .init(systemName: "millsign")),
    .naira: .init(title: "Nigerian naira", image: .init(systemName: "nairasign")),
    .norwegiankrone: .init(
      title: "Norwegian krone", image: .init(systemName: "norwegiankronesign")),
    .peruviansoles: .init(title: "Peruvian sol", image: .init(systemName: "peruviansolessign")),
    .peseta: .init(title: "Peseta", image: .init(systemName: "pesetasign")),
    .peso: .init(title: "Peso", image: .init(systemName: "pesosign")),
    .polishzloty: .init(title: "Polish złoty", image: .init(systemName: "polishzlotysign")),
    .ruble: .init(title: "Ruble", image: .init(systemName: "rublesign")),
    .rupee: .init(title: "Rupee", image: .init(systemName: "rupeesign")),
    .shekel: .init(title: "Shekel", image: .init(systemName: "shekelsign")),
    .singaporedollar: .init(
      title: "Singapore dollar", image: .init(systemName: "singaporedollarsign")),
    .sterling: .init(title: "Pound sterling", image: .init(systemName: "sterlingsign")),
    .swedishkrona: .init(title: "Swedish krona", image: .init(systemName: "swedishkronasign")),
    .tenge: .init(title: "Kazakh tenge", image: .init(systemName: "tengesign")),
    .tugrik: .init(title: "Mongolian tugrik", image: .init(systemName: "tugriksign")),
    .turkishlira: .init(title: "Turkish lira", image: .init(systemName: "turkishlirasign")),
    .won: .init(title: "Korean won", image: .init(systemName: "wonsign")),
    .yen: .init(title: "Yen", image: .init(systemName: "yensign"))
  ]
  var symbol: CurrencySymbol { CurrencySymbol(rawValue: rawValue) ?? .dollar }
}

struct CurrencyIconSettings: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Currency icon"
  @Parameter(title: "Symbol", default: .dollar) var symbol: CurrencySymbolChoice
  static var parameterSummary: some ParameterSummary { Summary { \.$symbol } }
}
