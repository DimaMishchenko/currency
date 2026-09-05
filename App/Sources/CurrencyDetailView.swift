import Charts
import CurrencyShared
import RateCore
import SwiftUI

struct CurrencyDetailSelection: Identifiable { let id: String }

struct CurrencyDetailView: View {
  let code: String
  let reference: String
  let book: RateBook
  @Environment(\.dismiss) private var dismiss
  @State private var days = 30
  @State private var series: HistorySeries?
  @State private var message: String?
  @State private var loading = false
  @State private var selectedDate: Date?
  private var quote: String {
    Currency.crypto.contains(code)
      ? "USD"
      : reference == code || Currency.crypto.contains(reference)
        ? (code == "EUR" ? "USD" : "EUR") : reference
  }
  private var selected: HistoryPoint? {
    guard let selectedDate else { return series?.points.last }
    return series?.points
      .min {
        abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
      }
  }
  private var domain: ClosedRange<Double> {
    let values = series?.points.map(\.value) ?? [0, 1]
    let low = values.min() ?? 0; let high = values.max() ?? 1
    let padding = max((high - low) * 0.15, max(high * 0.001, 0.00000001))
    return max(0, low - padding)...(high + padding)
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HStack(spacing: 12) {
            Text(Currency.flag(code)).font(.system(size: 36))
            VStack(alignment: .leading, spacing: 4) {
              Text(Currency.name(code)).font(.title2)
              Text("1 \(code) in \(quote)").font(.subheadline).foregroundStyle(.secondary)
            }
          }
          VStack(alignment: .leading, spacing: 6) {
            Text(rateLabel(book.convert(1, from: code, to: quote)))
              .font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
              .lineLimit(1).minimumScaleFactor(0.4)
            Text(book.details(from: code, to: quote)).font(.caption).foregroundStyle(.secondary)
            if let observed = book.quotes[code]?.observedAt {
              Text("Last trade \(observed.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          Divider()
          HStack {
            Text("HISTORY").font(.caption2.weight(.semibold)).tracking(2)
            Spacer()
            if loading { ProgressView().controlSize(.small) }
          }
          Picker("History range", selection: $days) {
            Text("1W").tag(7); Text("1M").tag(30); Text("3M").tag(90)
            Text("1Y").tag(365); Text("Max").tag(0)
          }
          .pickerStyle(.segmented)
          if let series, !series.points.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              if let selected {
                Text("\(rateLabel(Decimal(selected.value))) \(quote)")
                  .font(.title3.monospacedDigit())
                Text(dayLabel(selected.date))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
            .frame(height: 48, alignment: .leading)
            Chart(series.points) { point in
              LineMark(x: .value("Date", point.date), y: .value(quote, point.value))
                .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2))
              if selectedDate != nil, selected?.id == point.id {
                RuleMark(x: .value("Date", point.date)).foregroundStyle(.secondary.opacity(0.3))
                PointMark(x: .value("Date", point.date), y: .value(quote, point.value))
                  .foregroundStyle(Color.accentColor)
              }
            }
            .chartYScale(domain: domain).chartXSelection(value: $selectedDate)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 220)
            .accessibilityLabel(
              "\(days == 0 ? "All available" : days == 365 ? "One year" : "\(days) day") \(code) to \(quote) history"
            )
            Text(series.source).font(.caption).foregroundStyle(.secondary)
            if let first = series.points.first, let last = series.points.last {
              Text("\(dayLabel(first.date)) – \(dayLabel(last.date))").font(.caption2)
                .foregroundStyle(.secondary)
            }
            Text("Saved \(series.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption2).foregroundStyle(.secondary)
          } else if !loading {
            ContentUnavailableView(
              "No history available", systemImage: "chart.xyaxis.line",
              description: Text("Try another range or return when connected."))
          }
          if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
          if days == 0 {
            Text(
              "Max shows all history available from this provider for this pair, grouped monthly. It may begin after the currency launched."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          Text(
            Currency.crypto.contains(code)
              ? "Chart shows completed daily Coinbase trades in USD. Missing trading days have no observations. Current conversion rates may use Fawaz daily fallback."
              : "Daily reference rates. Weekends and publication gaps may have no observations. History uses Frankfurter; the converter keeps its ECB fallback."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        .padding(26)
      }
      .navigationTitle(code).navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .task(id: days) {
        loading = true; series = nil; selectedDate = nil; message = nil
        let result = await HistoryService(directory: SharedStore.directory)
          .load(base: code, quote: quote, days: days)
        guard !Task.isCancelled else { return }
        series = result.series; message = result.message; loading = false
      }
    }
  }
  private func rateLabel(_ value: Decimal?) -> String {
    guard let value else { return "—" }
    let formatter = NumberFormatter(); formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = Currency.crypto.contains(code) ? 2 : 6
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
  }
  private func dayLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium; formatter.timeStyle = .none
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }
}
