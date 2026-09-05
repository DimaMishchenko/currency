import Charts
import CurrencySupport
import ExchangeRates
import SwiftUI

/// Current rate provenance and on-demand historical charts for a currency.
public struct RateDetailsScreen: View {
  @Environment(\.locale) private var locale
  @Environment(AppAppearance.self) private var appearance
  @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 48
  private let history: HistoryService

  /// Creates details using a snapshot and an independently configured history service.
  public init(code: String, reference: String, snapshot: RateSnapshot, history: HistoryService) {
    self.code = code
    self.reference = reference
    self.snapshot = snapshot
    self.history = history
  }

  private let code: String
  private let reference: String
  private let snapshot: RateSnapshot
  @Environment(\.dismiss) private var dismiss
  @State private var range: HistoryRange = .month
  @State private var series: HistorySeries?
  @State private var message: LocalizedStringResource?
  @State private var loading = false
  @State private var selectedDate: Date?
  private var quote: String {
    let currency = CurrencyCode(rawValue: code)
    let referenceCurrency = CurrencyCode(rawValue: reference)
    if currency?.isCryptocurrency == true { return CurrencyCode.usd.rawValue }
    if reference == code || referenceCurrency?.isCryptocurrency == true {
      return currency == .eur ? CurrencyCode.usd.rawValue : CurrencyCode.eur.rawValue
    }
    return reference
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
    let low = values.min() ?? 0
    let high = values.max() ?? 1
    let padding = max((high - low) * 0.15, max(high * 0.001, 0.00000001))
    return max(0, low - padding)...(high + padding)
  }

  /// The rate details and history chart.
  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: AppStyle.Space.section) {
          HStack(spacing: AppStyle.Space.medium) {
            CurrencyIcon(code, size: 36)
            VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
              Text(CurrencyDisplay.name(code, locale: locale)).font(AppStyle.font(.title2))
              Text(.Details.unitConversion(code, quote)).font(AppStyle.font(.subheadline))
                .foregroundStyle(.secondary)
            }
          }
          VStack(alignment: .leading, spacing: AppStyle.Space.small) {
            Text(rateLabel(snapshot.convert(1, from: code, to: quote)))
              .font(.system(size: amountSize, weight: .light, design: .rounded)).monospacedDigit()
              .lineLimit(1).minimumScaleFactor(0.4)
            Text(CurrencyDisplay.details(snapshot, from: code, to: quote, locale: locale))
              .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
            if let observed = snapshot.quotes[code]?.observedAt {
              Text(

                .Details.lastTrade(
                  observed.formatted(.dateTime.day().month().year().hour().minute().locale(locale)))
              )
              .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
            }
            if let retrieved = snapshot.quotes[code]?.retrievedAt {
              Text(
                .Details.rateRetrieved(
                  retrieved.formatted(.dateTime.day().month().year().hour().minute().locale(locale))
                )
              )
              .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
            }
          }
          Divider()
          HStack {
            Text(.Details.historyHeading).font(AppStyle.font(.caption2).weight(.semibold))
              .tracking(2)
            Spacer()
            if loading { ProgressView().controlSize(.small) }
          }
          Picker(.Details.historyRange, selection: $range) {
            ForEach(HistoryRange.allCases, id: \.self) { range in
              Text(range.title).tag(range)
            }
          }
          .pickerStyle(.segmented)
          if let series, !series.points.isEmpty {
            VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
              if let selected {
                Text(verbatim: "\(rateLabel(Decimal(selected.value))) \(quote)")
                  .font(AppStyle.font(.title3).monospacedDigit())
                Text(dayLabel(selected.date))
                  .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
              }
            }
            .frame(minHeight: 48, alignment: .leading)
            Chart(series.points) { point in
              LineMark(
                x: .value(String(localized: .Details.chartDate), point.date),
                y: .value(quote, point.value)
              )
              .foregroundStyle(appearance.accent).lineStyle(StrokeStyle(lineWidth: 2))
              if selectedDate != nil, selected?.id == point.id {
                RuleMark(x: .value(String(localized: .Details.chartDate), point.date))
                  .foregroundStyle(.secondary.opacity(0.3))
                PointMark(
                  x: .value(String(localized: .Details.chartDate), point.date),
                  y: .value(quote, point.value)
                )
                .foregroundStyle(appearance.accent)
              }
            }
            .chartYScale(domain: domain).chartXSelection(value: $selectedDate)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 220)
            .accessibilityLabel(

              .Details.chartAccessibility(
                String(localized: range.accessibilityTitle), code, quote)
            )
            Text(RateMessages.providerDescription(series.source, locale: locale))
              .font(AppStyle.font(.caption))
              .foregroundStyle(.secondary)
            if let first = series.points.first, let last = series.points.last {
              Text(verbatim: "\(dayLabel(first.date)) – \(dayLabel(last.date))")
                .font(AppStyle.font(.caption2))
                .foregroundStyle(.secondary)
            }
            Text(

              .Details.savedAt(
                series.fetchedAt.formatted(
                  .dateTime.day().month().year().hour().minute().locale(locale)))
            )
            .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
          } else if !loading {
            ContentUnavailableView(
              .Details.noHistory, systemImage: "chart.xyaxis.line",
              description: Text(.Details.tryAnotherRange))
          }
          if let message { Text(message).font(AppStyle.font(.caption)).foregroundStyle(.secondary) }
          if range == .all {
            Text(
              .Details.maxExplanation
            )
            .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
          }
          Text(
            CurrencyCatalog.crypto.contains(code)
              ? .Details.cryptoExplanation
              : .Details.fiatExplanation
          )
          .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
        }
        .padding(AppStyle.Space.large)
      }
      .navigationTitle(code).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(.Details.done) { dismiss() }
        }
      }
      .task(id: range) {
        loading = true
        series = nil
        selectedDate = nil
        message = nil
        let result =
          await history
          .load(base: code, quote: quote, range: range)
        guard !Task.isCancelled else { return }
        series = result.series
        message = RateMessages.history(result.issue)
        loading = false
      }
    }
  }

  private func rateLabel(_ value: Decimal?) -> String {
    guard let value else { return "—" }
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = CurrencyCatalog.crypto.contains(code) ? 2 : 6
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
  }

  private func dayLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }
}
