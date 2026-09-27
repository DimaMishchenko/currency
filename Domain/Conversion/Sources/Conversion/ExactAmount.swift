import Foundation

/// Lossless text interchange for external calculations, independent of keypad limits.
public enum ExactAmount {
  /// Parses ungrouped nonnegative decimal text, rejecting silent Decimal rounding.
  public static func parse(_ text: String) -> Decimal? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: ".")
    guard !text.isEmpty, text.count <= 340,
      text.allSatisfy({ "0123456789.".contains($0) }),
      text.contains(where: { "0123456789".contains($0) }),
      text.filter({ $0 == "." }).count <= 1,
      let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
      !value.isNaN, value >= 0, normalized(text) == normalized(string(value))
    else { return nil }
    return value
  }

  /// Canonical dot-decimal text without grouping or scientific notation.
  public static func string(_ value: Decimal) -> String {
    let text = NSDecimalNumber(decimal: value).stringValue.lowercased()
    let parts = text.split(separator: "e")
    guard parts.count == 2, let exponent = Int(parts[1]) else { return text }
    let mantissa = String(parts[0])
    let negative = mantissa.hasPrefix("-")
    let unsigned = negative ? String(mantissa.dropFirst()) : mantissa
    let digits = unsigned.replacingOccurrences(of: ".", with: "")
    let point =
      (unsigned.firstIndex(of: ".").map { unsigned.distance(from: unsigned.startIndex, to: $0) }
        ?? unsigned.count) + exponent
    let expanded: String
    if point <= 0 {
      expanded = "0." + String(repeating: "0", count: -point) + digits
    } else if point >= digits.count {
      expanded = digits + String(repeating: "0", count: point - digits.count)
    } else {
      let index = digits.index(digits.startIndex, offsetBy: point)
      expanded = String(digits[..<index]) + "." + String(digits[index...])
    }
    return (negative ? "-" : "") + normalized(expanded)
  }

  private static func normalized(_ text: String) -> String {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    let integer = String(parts[0].drop(while: { $0 == "0" }))
    let fraction =
      parts.count == 2 ? String(parts[1].reversed().drop(while: { $0 == "0" }).reversed()) : ""
    return (integer.isEmpty ? "0" : integer) + (fraction.isEmpty ? "" : "." + fraction)
  }
}
