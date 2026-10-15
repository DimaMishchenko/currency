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
      directory: directory, client: CryptoHistoryFixture())
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
    if url.host == "community-api.coinmetrics.io" {
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      guard let rawEnd = query.first(where: { $0.name == "end_time" })?.value,
        let end = ISO8601DateFormatter().date(from: rawEnd)
      else { throw RateError.invalidData }
      let rows: [[String: String]] = (0...1440)
        .map { index -> [String: String] in
          let offset: TimeInterval = Double(index - 1440) * 60
          let time: String = end.addingTimeInterval(offset).ISO8601Format()
          let price: Double = 83_055 + Double(index) * 1553.1 / 1440
          return [
            "asset": "btc", "time": time, "ReferenceRateUSD": String(price)
          ]
        }
      return try JSONSerialization.data(withJSONObject: ["data": rows])
    }
    guard url.host == "cdn.jsdelivr.net" || url.host?.hasSuffix("currency-api.pages.dev") == true
    else { throw RateError.unavailable }
    let date =
      url.path.components(separatedBy: "@").last?.components(separatedBy: "/").first
      ?? "2026-09-30"
    return try JSONSerialization.data(withJSONObject: [
      "date": date, "eur": ["usd": 1, "btc": 1 / 84_000.0]
    ])
  }
}
