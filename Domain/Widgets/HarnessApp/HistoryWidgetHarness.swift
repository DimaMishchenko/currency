import Conversion
import ExchangeRates
import LocalCurrency
import SwiftUI
import WidgetKit
import Widgets
import WidgetsUI

/// Deterministic scenarios exercise the production layout without writing shared app data.
struct HistoryWidgetHarness: View {
  let scenario: String
  private let date = Date(timeIntervalSince1970: 1_790_035_200)

  private var entry: HistoryWidgetEntry {
    let preview = HistoryWidgetEntry.preview(date: date)
    guard let source = preview.snapshot.series else { return preview }
    let values: [Double]
    switch scenario {
    case "history-down":
      values = [25.04, 24.96, 25.00, 24.82, 24.9, 24.78, 24.8, 24.65, 24.7, 24.32]
    case "history-flat": values = Array(repeating: 25, count: 10)
    case "history-tiny":
      values = [
        0.00012, 0.000121, 0.000122, 0.000119, 0.000125, 0.00013, 0.000129, 0.000131, 0.000130,
        0.000132
      ]
    case "history-usd-btc":
      values = [
        62_000, 63_000, 61_500, 64_000, 65_000, 64_500, 66_000, 67_000, 66_500, 68_000
      ]
    default: values = source.points.map(\.value)
    }
    let local = scenario.hasPrefix("history-local")
    let missing = local || scenario == "history-unavailable" || scenario == "history-unsupported"
    let points = zip(source.points, values).map { HistoryPoint(date: $0.date, value: $1) }
    let pair = HistoryWidgetPair(
      app: ConverterState(),
      base: scenario == "history-unsupported"
        ? "BTC" : scenario == "history-usd-btc" ? "USD" : "EUR",
      quote: local ? WidgetSelection.localID : scenario == "history-usd-btc" ? "BTC" : "CZK")
    return HistoryWidgetEntry(
      date: date,
      snapshot: HistoryWidgetSnapshot(
        pair: pair, range: .month,
        result: HistoryResult(
          series: missing
            ? nil : HistorySeries(points: points, source: source.source, fetchedAt: date),
          issue: scenario == "history-cached" ? .usingCachedSeries : missing ? .unavailable : nil)),
      locationStatus: scenario == "history-local-denied" ? .denied : .notDetermined)
  }

  var body: some View {
    VStack(spacing: 28) {
      widget(.systemMedium, width: 344, height: 164)
      widget(.systemSmall, width: 164, height: 164)
      widget(.systemMedium, width: 344, height: 164).environment(\.colorScheme, .dark)
    }
    .padding(.vertical, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .secondarySystemBackground))
    .environment(\.isWidgetPreview, true)
  }

  private func widget(_ family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
    HistoryWidgetView(entry: entry, family: family)
      .frame(width: width, height: height)
      .clipShape(.rect(cornerRadius: 24))
  }
}
