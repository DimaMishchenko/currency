import CoordinatedFiles
import CryptoKit
import ExchangeRates
import Foundation

/// Retains immutable rendered quotes without modifying the authoritative rate cache.
public struct WidgetQuoteContextStore: Sendable {
  /// Immutable rates and optional configured pair retained for widget navigation.
  public struct Context: Sendable {
    /// Rates used when the widget rendered.
    public let snapshot: RateSnapshot
    /// Configured source currency, or nil for a converter-following context.
    public let base: String?
    /// Configured comparison currency, or nil for a converter-following context.
    public let quote: String?
    /// Selected period for a History widget destination.
    public let historyRange: HistoryRange?
    /// Measurement captured with a History widget destination.
    public let metalUnit: MetalUnit?
  }
  private struct Record: Codable {
    let id: UUID
    let digest: String
    let createdAt: Date
    let snapshot: RateSnapshot
    let base: String?
    let quote: String?
    let historyRange: Int?
    let metalUnit: MetalUnit?
  }
  private struct IndexEntry: Codable {
    let id: UUID
    let digest: String
    let createdAt: Date
  }
  private let directory: URL
  /// Maximum age, in seconds, of a context accepted for navigation.
  public static let lifetime: TimeInterval = 7 * 86_400
  /// Maximum number of distinct rendered contexts retained on disk.
  public static let capacity = 128

  /// Uses the host-supplied shared directory to retain widget contexts.
  public init(directory: URL) { self.directory = directory }
  private var legacyURL: URL { directory.appendingPathComponent("widget-quote-contexts.json") }
  private var recordsDirectory: URL { directory.appendingPathComponent("widget-quote-contexts-v2") }
  private var indexURL: URL { recordsDirectory.appendingPathComponent("index.json") }
  private func recordURL(_ id: UUID) -> URL {
    recordsDirectory.appendingPathComponent(id.uuidString + ".json")
  }

  /// Saves one context per distinct rendered snapshot and returns a price-free navigation URL.
  public func save(
    _ snapshot: RateSnapshot, base: String? = nil, quote: String? = nil,
    historyRange: HistoryRange? = nil, metalUnit: MetalUnit? = nil, now: Date = .now
  ) throws -> URL? {
    guard !snapshot.quotes.isEmpty else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let destination =
      ":" + (base ?? "") + ":" + (quote ?? "")
      + ":" + (historyRange.map { String($0.rawValue) } ?? "")
      + ":" + (metalUnit?.rawValue ?? "")
    let digest =
      SHA256.hash(
        data: try encoder.encode(snapshot) + Data(destination.utf8)
      )
      .map { String(format: "%02x", $0) }
      .joined()
    return try FileCoordination.write(at: indexURL) {
      let saved = try readIndex()
      var entries = saved.filter { validDate($0.createdAt, now: now) }
      let entry =
        entries.first { $0.digest == digest }
        ?? IndexEntry(id: UUID(), digest: digest, createdAt: now)
      if !entries.contains(where: { $0.id == entry.id })
        || !FileManager.default.fileExists(atPath: recordURL(entry.id).path)
      {
        let record = Record(
          id: entry.id, digest: digest, createdAt: entry.createdAt, snapshot: snapshot,
          base: base, quote: quote, historyRange: historyRange?.rawValue, metalUnit: metalUnit)
        try encoder.encode(record).write(to: recordURL(entry.id), options: .atomic)
      }
      entries.removeAll { $0.id == entry.id }
      entries.append(entry)
      entries = Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(Self.capacity))
      try encoder.encode(entries).write(to: indexURL, options: .atomic)
      let retained = Set(entries.map(\.id))
      let files = try FileManager.default.contentsOfDirectory(
        at: recordsDirectory, includingPropertiesForKeys: nil)
      for file in files where file.pathExtension == "json" {
        guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
          !retained.contains(id)
        else { continue }
        try FileManager.default.removeItem(at: file)
      }
      return URL(string: "currency://widget?v=1&context=\(entry.id.uuidString)")
    }
  }

  /// Returns the saved snapshot after per-record lookup and any applicable legacy fallback.
  /// Returns nil if the selected record is missing, expired, future-dated or has no quotes.
  public func load(_ id: UUID, now: Date = .now) -> RateSnapshot? {
    context(id, now: now)?.snapshot
  }

  /// Returns a valid saved context, or nil when it is missing, expired or unreadable.
  public func context(_ id: UUID, now: Date = .now) -> Context? {
    let record: Record?
    if let data = try? FileCoordination.dataIfPresent(at: recordURL(id)),
      data.count <= 1_048_576,
      let saved = try? JSONDecoder().decode(Record.self, from: data), saved.id == id
    {
      record = saved
    } else {
      record = try? readLegacy().first { $0.id == id }
    }
    guard let record, valid(record, now: now) else { return nil }
    return Context(
      snapshot: record.snapshot, base: record.base, quote: record.quote,
      historyRange: record.historyRange.flatMap(HistoryRange.init(rawValue:)),
      metalUnit: record.metalUnit)
  }

  private func readIndex() throws -> [IndexEntry] {
    guard let data = try FileCoordination.dataIfPresent(at: indexURL) else { return [] }
    guard data.count <= 65_536 else { throw CocoaError(.fileReadCorruptFile) }
    let entries = try JSONDecoder().decode([IndexEntry].self, from: data)
    guard entries.count <= Self.capacity else { throw CocoaError(.fileReadCorruptFile) }
    return entries
  }

  private func readLegacy() throws -> [Record] {
    guard let data = try FileCoordination.dataIfPresent(at: legacyURL), data.count <= 16_777_216
    else {
      return []
    }
    return try JSONDecoder().decode([Record].self, from: data)
  }

  private func validDate(_ date: Date, now: Date) -> Bool {
    date <= now && now.timeIntervalSince(date) < Self.lifetime
  }

  private func valid(_ record: Record, now: Date) -> Bool {
    validDate(record.createdAt, now: now) && !record.snapshot.quotes.isEmpty
  }
}
