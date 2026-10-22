import CoordinatedFiles
import CryptoKit
import ExchangeRates
import Foundation

extension WidgetStore {
  /// Claims one sibling-history reload per distinct canonical pair endpoint across processes.
  /// An older observation never replaces a more recent claimed endpoint.
  public func claimHistoryQuoteRefresh(
    base: String, quote: String, point: HistoryPoint
  ) throws -> Bool {
    guard point.value.isFinite, point.value > 0 else { return false }
    let digest = SHA256.hash(data: Data((base + ":" + quote).utf8))
      .map { String(format: "%02x", $0) }.joined()
    let filename = "history-quote-refresh-" + digest + ".json"
    let url = directory.appendingPathComponent(filename)
    return try coordinate(filename) {
      if let data = try FileCoordination.dataIfPresent(at: url) {
        let previous = try JSONDecoder().decode(HistoryPoint.self, from: data)
        guard previous != point, previous.date <= point.date else { return false }
      }
      try JSONEncoder().encode(point).write(to: url, options: .atomic)
      return true
    }
  }
}
