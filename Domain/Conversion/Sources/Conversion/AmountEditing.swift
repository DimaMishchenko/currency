import Foundation

/// Shared parsing rules for editable, nonnegative currency amounts.
public enum AmountEditing {
  /// Parses a nonnegative configured amount without accepting grouping or exponent syntax.
  public static func parseAmount(_ text: String) -> Decimal? {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: ".")
    guard !normalized.isEmpty, normalized.count <= 30,
      normalized.allSatisfy({ "0123456789.".contains($0) }),
      normalized.filter({ $0 == "." }).count <= 1,
      let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
      !value.isNaN, value >= 0
    else { return nil }
    return value
  }

}
