import ExchangeRates
import Foundation

extension HistoryRange {
  var title: LocalizedStringResource {
    switch self {
    case .week: .Details.week
    case .month: .Details.month
    case .quarter: .Details.quarter
    case .year: .Details.year
    case .all: .Details.all
    }
  }

  var accessibilityTitle: LocalizedStringResource {
    switch self {
    case .week: .Details.weekAccessibility
    case .month: .Details.monthAccessibility
    case .quarter: .Details.quarterAccessibility
    case .year: .Details.yearAccessibility
    case .all: .Details.allAccessibility
    }
  }
}
