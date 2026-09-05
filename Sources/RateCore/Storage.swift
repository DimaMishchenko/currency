import Foundation

/// The persisted converter input shared by the app and widgets.
public struct InputState: Codable, Sendable, Equatable {
  /// The user's ordered destination currencies.
  public var savedTargets: [String]? = nil
  /// The time of the most recent input edit.
  public var editedAt: Date? = nil
  /// The source amount as editable decimal text.
  public var amount = "1"
  /// The source currency code.
  public var from = "EUR"
  /// The primary destination currency code.
  public var to = "USD"
  /// Creates the default converter input.
  public init() {}
  /// The source amount parsed as a decimal value.
  public var decimal: Decimal {
    Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
  }
  /// Applies a keypad command to the input.
  public mutating func press(_ key: String) {
    editedAt = Date()
    switch key {
    case "00": press("0"); press("0")
    case "AC": amount = "0"
    case "⌫": amount = amount.count > 1 ? String(amount.dropLast()) : "0"
    case "⇅": changeSource(to)
    case ".", ",": if !amount.contains(".") { amount += "." }
    default:
      guard key.count == 1, "0123456789".contains(key), amount.filter({ $0 != "." }).count < 14
      else { return }
      if amount == "0" { amount = key } else { amount += key }
    }
  }
}

/// An atomic disk-backed store for rate snapshots.
public struct DiskStore: Sendable {
  /// The directory that contains the rate snapshot.
  public let directory: URL
  /// Creates a store rooted at a directory.
  public init(directory: URL) { self.directory = directory }
  /// Loads a valid saved rate book or returns an empty one.
  public func load() -> RateBook {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("rates.json")),
      let book = try? JSONDecoder().decode(RateBook.self, from: data),
      book.quotes.values.allSatisfy({ $0.value > 0 && !$0.value.isNaN })
    else { return RateBook() }
    return book
  }
  /// Saves a rate book atomically.
  public func save(_ book: RateBook) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(book)
      .write(to: directory.appendingPathComponent("rates.json"), options: .atomic)
  }
}
