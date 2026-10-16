import CoordinatedFiles
import CryptoKit
import ExchangeRates
import Foundation

/// Retains immutable rendered quotes without modifying the authoritative rate cache.
public struct WidgetQuoteContextStore: Sendable {
  public struct Context: Sendable {
    public let snapshot: RateSnapshot
    public let base: String?
    public let quote: String?
  }
  private struct Record: Codable {
    let id: UUID
    let digest: String
    let createdAt: Date
    let snapshot: RateSnapshot
    let base: String?
    let quote: String?
  }
  private let directory: URL
  public static let lifetime: TimeInterval = 7 * 86_400
  public static let capacity = 128

  public init(directory: URL) { self.directory = directory }
  private var url: URL { directory.appendingPathComponent("widget-quote-contexts.json") }

  /// Saves one context per distinct rendered snapshot and returns a price-free navigation URL.
  public func save(
    _ snapshot: RateSnapshot, base: String? = nil, quote: String? = nil,
    now: Date = .now
  ) throws -> URL? {
    guard !snapshot.quotes.isEmpty else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let digest =
      SHA256.hash(
        data: try encoder.encode(snapshot) + Data((":" + (base ?? "") + ":" + (quote ?? "")).utf8)
      )
      .map { String(format: "%02x", $0) }
      .joined()
    return try FileCoordination.write(at: url) {
      var records = try read().filter { valid($0, now: now) }
      let record =
        records.first { $0.digest == digest }
        ?? Record(
          id: UUID(), digest: digest, createdAt: now, snapshot: snapshot, base: base, quote: quote)
      records.removeAll { $0.id == record.id }
      records.append(record)
      records = Array(records.sorted { $0.createdAt > $1.createdAt }.prefix(Self.capacity))
      try encoder.encode(records).write(to: url, options: .atomic)
      return URL(string: "currency://widget?v=1&context=\(record.id.uuidString)")
    }
  }

  /// Missing, expired or incompatible contexts fall back to the app's current quotes.
  public func load(_ id: UUID, now: Date = .now) -> RateSnapshot? {
    context(id, now: now)?.snapshot
  }

  public func context(_ id: UUID, now: Date = .now) -> Context? {
    guard let record = try? read().first(where: { $0.id == id && valid($0, now: now) }) else {
      return nil
    }
    return Context(snapshot: record.snapshot, base: record.base, quote: record.quote)
  }

  private func read() throws -> [Record] {
    guard let data = try FileCoordination.dataIfPresent(at: url), data.count <= 16_777_216 else {
      return []
    }
    return try JSONDecoder().decode([Record].self, from: data)
  }

  private func valid(_ record: Record, now: Date) -> Bool {
    record.createdAt <= now && now.timeIntervalSince(record.createdAt) < Self.lifetime
      && !record.snapshot.quotes.isEmpty
  }
}
