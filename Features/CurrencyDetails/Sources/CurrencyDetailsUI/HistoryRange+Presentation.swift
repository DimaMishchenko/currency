import CurrencyDetails
import ExchangeRates
import Foundation

extension HistoryRange {
  var title: LocalizedStringResource {
    switch self {
    case .day: .Details.day
    case .week: .Details.week
    case .month: .Details.month
    case .quarter: .Details.quarter
    case .yearToDate: .Details.yearToDate
    case .year: .Details.year
    case .all: .Details.all
    }
  }

  var accessibilityTitle: LocalizedStringResource {
    switch self {
    case .day: .Details.dayAccessibility
    case .week: .Details.weekAccessibility
    case .month: .Details.monthAccessibility
    case .quarter: .Details.quarterAccessibility
    case .yearToDate: .Details.yearToDateAccessibility
    case .year: .Details.yearAccessibility
    case .all: .Details.allAccessibility
    }
  }
}
