import Foundation

public struct InputState: Codable, Sendable, Equatable {
    public var savedTargets: [String]? = nil
    public var editedAt: Date? = nil
    public var amount = "1"
    public var from = "EUR"
    public var to = "USD"
    public init() {}
    public var decimal: Decimal { Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    public mutating func press(_ key: String) {
        editedAt = Date()
        switch key {
        case "00": press("0"); press("0")
        case "AC": amount = "0"
        case "⌫": amount = amount.count > 1 ? String(amount.dropLast()) : "0"
        case "⇅": changeSource(to)
        case ".", ",": if !amount.contains(".") { amount += "." }
        default:
            guard key.count == 1, "0123456789".contains(key), amount.filter({ $0 != "." }).count < 14 else { return }
            if amount == "0" { amount = key } else { amount += key }
        }
    }
}

public struct DiskStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load() -> RateBook {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("rates.json")), let book = try? JSONDecoder().decode(RateBook.self, from: data), book.quotes.values.allSatisfy({ $0.value > 0 && !$0.value.isNaN }) else { return RateBook() }
        return book
    }
    public func save(_ book: RateBook) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(book).write(to: directory.appendingPathComponent("rates.json"), options: .atomic)
    }
}
