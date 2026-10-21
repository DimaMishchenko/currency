import ExchangeRates
import Foundation

struct HistoryDatePresentation {
  let range: HistoryRange
  let observation: RateObservation?
  let locale: Locale
  let timeZone: TimeZone

  var showsTime: Bool {
    switch observation {
    case .minuteReference, .hourlyReference: true
    case nil: range == .day
    default: false
    }
  }

  var axisFormat: Date.FormatStyle {
    var format: Date.FormatStyle =
      switch range {
      case .day: .dateTime.hour().minute()
      case .all: .dateTime.year()
      default: .dateTime.day().month(.abbreviated)
      }
    format.locale = locale
    format.timeZone = showsTime ? timeZone : .gmt
    return format
  }

  var timestampFormat: Date.FormatStyle {
    var format = Date.FormatStyle.dateTime.day().month().year().hour().minute().locale(locale)
    format.timeZone = timeZone
    return format
  }

  var chartTimeZone: String {
    timeZone.localizedName(for: .generic, locale: locale) ?? timeZone.identifier
  }

  func pointLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateStyle = .medium
    formatter.timeStyle = showsTime ? .short : .none
    formatter.timeZone = showsTime ? timeZone : .gmt
    return formatter.string(from: date)
  }
}
