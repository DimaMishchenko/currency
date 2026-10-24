import CoordinatedFiles
import Foundation

/// Shared successful-conversion usage used to claim an App Store review request.
public struct ConversionUsageStore: Sendable {
  private let directory: URL

  /// Creates a store in an explicitly supplied shared or isolated directory.
  public init(directory: URL) { self.directory = directory }

  /// Records one completed app conversion without grouping separate app actions.
  public func recordConversion() throws {
    try update { $0.count = min($0.count + 1, 3) }
  }

  /// Records a widget edit, grouping consecutive edits less than 30 seconds apart per key.
  /// Every accepted edit updates that widget's activity, including grouped edits.
  public func recordWidgetConversion(key: String, now: Date) throws {
    guard now.timeIntervalSince1970.isFinite else { throw CocoaError(.coderInvalidValue) }
    try update { record in
      let elapsed = record.widgetActivity[key].map { now.timeIntervalSince($0) }
      if elapsed.map({ $0 >= 30 || $0 < 0 }) ?? true {
        record.count = min(record.count + 1, 3)
      }
      record.widgetActivity[key] = now
    }
  }

  /// Atomically claims eligibility after three conversions and resets the shared counter.
  /// A failed read or write throws without replacing the previous record.
  public func claimReviewRequest() throws -> Bool {
    try update { record in
      guard record.count >= 3 else { return false }
      record.count = 0
      return true
    }
  }

  private struct Record: Codable {
    var version = 1
    var count = 0
    var widgetActivity: [String: Date] = [:]
  }

  private func update<Value>(_ mutation: (inout Record) throws -> Value) throws -> Value {
    let url = directory.appendingPathComponent("conversion-usage.json")
    return try FileCoordination.write(at: url) {
      var record =
        try FileCoordination.dataIfPresent(at: url)
        .map {
          try JSONDecoder().decode(Record.self, from: $0)
        } ?? Record()
      guard record.version == 1, (0...3).contains(record.count),
        record.widgetActivity.values.allSatisfy({ $0.timeIntervalSince1970.isFinite })
      else { throw CocoaError(.coderReadCorrupt) }
      let result = try mutation(&record)
      try JSONEncoder().encode(record).write(to: url, options: .atomic)
      return result
    }
  }
}
