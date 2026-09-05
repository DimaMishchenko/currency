import Foundation

func validDate(_ value: String) -> Bool {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.dateFormat = "yyyy-MM-dd"

  formatter.isLenient = false
  guard let date = formatter.date(from: value) else { return false }
  return formatter.string(from: date) == value && date < Date().addingTimeInterval(86400)
}
