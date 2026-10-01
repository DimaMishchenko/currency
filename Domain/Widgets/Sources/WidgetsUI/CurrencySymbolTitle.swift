import Foundation
import Widgets

public extension CurrencySymbol {
  /// Localized name for symbol pickers and accessibility.
  var localizedTitle: LocalizedStringResource {
    switch self {
    case .austral: .WidgetPresentation.symbolAustral
    case .australiandollar: .WidgetPresentation.symbolAustraliandollar
    case .baht: .WidgetPresentation.symbolBaht
    case .bitcoin: .WidgetPresentation.symbolBitcoin
    case .brazilianreal: .WidgetPresentation.symbolBrazilianreal
    case .cedi: .WidgetPresentation.symbolCedi
    case .cent: .WidgetPresentation.symbolCent
    case .chineseyuanrenminbi: .WidgetPresentation.symbolChineseyuanrenminbi
    case .coloncurrency: .WidgetPresentation.symbolColoncurrency
    case .cruzeiro: .WidgetPresentation.symbolCruzeiro
    case .danishkrone: .WidgetPresentation.symbolDanishkrone
    case .dong: .WidgetPresentation.symbolDong
    case .dollar: .WidgetPresentation.symbolDollar
    case .euro: .WidgetPresentation.symbolEuro
    case .eurozone: .WidgetPresentation.symbolEurozone
    case .florin: .WidgetPresentation.symbolFlorin
    case .franc: .WidgetPresentation.symbolFranc
    case .guarani: .WidgetPresentation.symbolGuarani
    case .hryvnia: .WidgetPresentation.symbolHryvnia
    case .indianrupee: .WidgetPresentation.symbolIndianrupee
    case .kip: .WidgetPresentation.symbolKip
    case .lari: .WidgetPresentation.symbolLari
    case .lira: .WidgetPresentation.symbolLira
    case .malaysianringgit: .WidgetPresentation.symbolMalaysianringgit
    case .manat: .WidgetPresentation.symbolManat
    case .mill: .WidgetPresentation.symbolMill
    case .naira: .WidgetPresentation.symbolNaira
    case .norwegiankrone: .WidgetPresentation.symbolNorwegiankrone
    case .peruviansoles: .WidgetPresentation.symbolPeruviansoles
    case .peseta: .WidgetPresentation.symbolPeseta
    case .peso: .WidgetPresentation.symbolPeso
    case .polishzloty: .WidgetPresentation.symbolPolishzloty
    case .ruble: .WidgetPresentation.symbolRuble
    case .rupee: .WidgetPresentation.symbolRupee
    case .shekel: .WidgetPresentation.symbolShekel
    case .singaporedollar: .WidgetPresentation.symbolSingaporedollar
    case .sterling: .WidgetPresentation.symbolSterling
    case .swedishkrona: .WidgetPresentation.symbolSwedishkrona
    case .tenge: .WidgetPresentation.symbolTenge
    case .tugrik: .WidgetPresentation.symbolTugrik
    case .turkishlira: .WidgetPresentation.symbolTurkishlira
    case .won: .WidgetPresentation.symbolWon
    case .yen: .WidgetPresentation.symbolYen
    }
  }
}
