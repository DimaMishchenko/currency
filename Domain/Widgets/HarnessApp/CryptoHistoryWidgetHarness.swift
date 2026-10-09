import Conversion
import ExchangeRates
import Foundation
import SwiftUI
import WidgetKit
import Widgets
import WidgetsUI

struct CryptoHistoryWidgetHarness: View {
  @State private var entries: [HistoryRange: HistoryWidgetEntry] = [:]
  private let date = Date(timeIntervalSince1970: 1_790_782_680)

  var body: some View {
    VStack(spacing: 28) {
      widget(.week, family: .systemMedium, width: 344, height: 164)
      widget(.day, family: .systemSmall, width: 164, height: 164)
      widget(.month, family: .systemMedium, width: 344, height: 164)
        .environment(\.colorScheme, .dark)
    }
    .padding(.vertical, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .secondarySystemBackground))
    .environment(\.isWidgetPreview, true)
    .task { await load() }
  }

  private func widget(
    _ range: HistoryRange, family: WidgetFamily, width: CGFloat, height: CGFloat
  ) -> some View {
    let entry =
      entries[range]
      ?? HistoryWidgetEntry(
        date: date,
        snapshot: HistoryWidgetSnapshot(
          pair: HistoryWidgetPair(app: ConverterState(), base: "BTC", quote: "USD"), range: range,
          result: HistoryResult(series: nil, issue: .unavailable)))
    return HistoryWidgetView(entry: entry, family: family)
      .frame(width: width, height: height)
      .clipShape(.rect(cornerRadius: 24))
  }

  private func load() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let history = HistoryService(
      directory: directory, client: CryptoHistoryFixture(), policy: .coinbaseEnhanced)
    let pair = HistoryWidgetPair(app: ConverterState(), base: "BTC", quote: "USD")
    for range: HistoryRange in [.day, .week, .month] {
      let result = await history.load(base: "BTC", quote: "USD", range: range, now: date)
      guard !Task.isCancelled else { return }
      entries[range] = HistoryWidgetEntry(
        date: date, snapshot: HistoryWidgetSnapshot(pair: pair, range: range, result: result))
    }
  }
}

private struct CryptoHistoryFixture: HTTPClient {
  func get(_ url: URL) async throws -> Data {
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let hourly = query.first { $0.name == "granularity" }?.value == "3600"
    let rows: [(String, Double)] =
      hourly
      ? [("2026-09-29T18:00:00Z", 83_055), ("2026-09-30T14:00:00Z", 84_608.1)]
      : [
        ("2026-09-05T00:00:00Z", 81_000), ("2026-09-23T00:00:00Z", 84_381),
        ("2026-09-26T00:00:00Z", 84_100), ("2026-09-29T00:00:00Z", 83_638.4)
      ]
    return try JSONEncoder()
      .encode(
        rows.map { date, value in
          guard let observation = ISO8601DateFormatter().date(from: date) else {
            throw RateError.invalidData
          }
          return [
            observation.timeIntervalSince1970,
            value, value, value, value, 1
          ]
        })
  }
}
