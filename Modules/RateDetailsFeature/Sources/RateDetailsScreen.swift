import Charts
import CurrencySupport
import ExchangeRates
import SwiftUI

/// Current rate provenance and on-demand historical charts for a currency.
public struct RateDetailsScreen: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.locale) private var locale
  @Environment(AppAppearance.self) private var appearance
  @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 48
  @ScaledMetric(relativeTo: .caption2) private var axisWidth = 52
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
  @State private var loading = true
  @State private var reveal: CGFloat = 0
  @State private var titleHeight: CGFloat = 60
  @State private var compactTitle = false
  private var currencyName: String { CurrencyDisplay.name(code, locale: locale) }

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
              Text(currencyName).font(AppStyle.font(.title2, weight: .semibold))
              Text(.Details.unitConversion(code, quote)).font(AppStyle.font(.subheadline))
                .foregroundStyle(.secondary)
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(.isHeader)
          .onGeometryChange(for: CGFloat.self) {
            $0.size.height
          } action: {
            titleHeight = $0
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
          VStack(alignment: .leading, spacing: AppStyle.Space.large) {
            Text(.Details.historyHeading).font(AppStyle.font(.caption2, weight: .semibold))
              .tracking(2)
            Picker(.Details.historyRange, selection: $range) {
              ForEach(HistoryRange.allCases, id: \.self) { range in
                Text(range.title).tag(range)
              }
            }
            .pickerStyle(.segmented)
            historyContent
            historyFooter
          }
        }
        .padding(AppStyle.Space.large)
      }
      .onScrollGeometryChange(for: Bool.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top > titleHeight + AppStyle.Space.large
      } action: { _, collapsed in
        compactTitle = collapsed
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          HStack(spacing: AppStyle.Space.small) {
            CurrencyIcon(code, size: 20).accessibilityHidden(true)
            Text(dynamicTypeSize.isAccessibilitySize ? code : currencyName)
              .font(AppStyle.font(.headline)).lineLimit(1)
          }
          .opacity(compactTitle ? 1 : 0)
          .accessibilityHidden(!compactTitle)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(.Details.close, systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
        }
      }
      .task(id: range) {
        reveal = 0
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
        guard result.series?.points.isEmpty == false else { return }
        if reduceMotion {
          reveal = 1
        } else {
          // Let the accepted final domains lay out before revealing the plot.
          await Task.yield()
          guard !Task.isCancelled else { return }
          withAnimation(.easeOut(duration: 0.55)) { reveal = 1 }
        }
      }
    }
  }

  private var historyContent: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.medium) {
      ZStack(alignment: .leading) {
        // Real typography reserves enough space at every Dynamic Type size.
        VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
          Text(verbatim: "0.000000 \(quote)").font(AppStyle.font(.title3))
          Text(dayLabel(Date())).font(AppStyle.font(.caption))
        }
        .hidden().accessibilityHidden(true)
        if let selected, !loading {
          VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
            Text(verbatim: "\(rateLabel(Decimal(selected.value))) \(quote)")
              .font(AppStyle.font(.title3).monospacedDigit())
            Text(dayLabel(selected.date))
              .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
          }
        } else if loading {
          VStack(alignment: .leading, spacing: AppStyle.Space.small) {
            RoundedRectangle(cornerRadius: 4).frame(width: 150, height: 18)
            RoundedRectangle(cornerRadius: 3).frame(width: 96, height: 10)
          }
          .foregroundStyle(.quaternary).accessibilityHidden(true)
        }
      }
      .frame(minHeight: 48, alignment: .leading)
      Group {
        if loading {
          HistorySkeleton(
            reduceMotion: reduceMotion, axisWidth: axisWidth,
            singleDateLabel: dynamicTypeSize.isAccessibilitySize
          )
          .frame(height: 220)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(.Details.loadingHistory)
        } else if let series, !series.points.isEmpty {
          historyChart(series).frame(height: 220)
        } else {
          ContentUnavailableView(
            .Details.noHistory, systemImage: "chart.xyaxis.line",
            description: Text(.Details.tryAnotherRange)
          )
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(minHeight: 220)
    }
  }

  private func historyChart(_ series: HistorySeries) -> some View {
    Chart(series.points) { point in
      LineMark(
        x: .value(String(localized: .Details.chartDate), point.date),
        y: .value(quote, point.value)
      )
      .foregroundStyle(appearance.accent).opacity(0)
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
    .chartYScale(domain: domain)
    .chartXSelection(value: $selectedDate)
    .chartYAxis {
      AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine()
        AxisValueLabel {
          if let number = value.as(Double.self) {
            Text(number.formatted(.number.precision(.significantDigits(1...4)).locale(locale)))
              .font(AppStyle.font(.caption2)).frame(width: axisWidth, alignment: .leading)
          }
        }
      }
    }
    .chartXAxis {
      if dynamicTypeSize.isAccessibilitySize {
        AxisMarks(values: [series.points[series.points.count / 2].date]) { value in
          historyDateMark(value)
        }
      } else {
        AxisMarks(values: .automatic(desiredCount: 3)) { value in
          historyDateMark(value)
        }
      }
    }
    .chartOverlay { proxy in
      GeometryReader { geometry in
        if let anchor = proxy.plotFrame {
          let plot = geometry[anchor]
          // Keep native axes, selection and accessibility stable; reveal only the real line.
          Path { path in
            for (index, point) in series.points.enumerated() {
              if let x = proxy.position(forX: point.date), let y = proxy.position(forY: point.value)
              {
                let position = CGPoint(x: x, y: y)
                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
              }
            }
          }
          .stroke(appearance.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
          .frame(width: plot.width, height: plot.height)
          .mask(alignment: .leading) {
            Rectangle().scaleEffect(x: reduceMotion ? 1 : reveal, y: 1, anchor: .leading)
          }
          .offset(x: plot.minX, y: plot.minY)
          .accessibilityHidden(true)
        }
      }
      .allowsHitTesting(false)
    }
    .accessibilityLabel(
      .Details.chartAccessibility(String(localized: range.accessibilityTitle), code, quote))
  }

  @AxisMarkBuilder
  private func historyDateMark(_ value: AxisValue) -> some AxisMark {
    AxisGridLine()
    AxisValueLabel {
      if let date = value.as(Date.self) {
        Text(
          date.formatted(
            range == .all
              ? .dateTime.year().locale(locale)
              : .dateTime.day().month(.abbreviated).locale(locale))
        )
        .font(AppStyle.font(.caption2)).fixedSize()
      }
    }
  }

  private var historyFooter: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.medium) {
      if let series, !series.points.isEmpty {
        VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
          Text(RateMessages.providerDescription(series.source, locale: locale))
          if let first = series.points.first, let last = series.points.last {
            Text(verbatim: "\(dayLabel(first.date)) – \(dayLabel(last.date))")
          }
          Text(
            .Details.savedAt(
              series.fetchedAt.formatted(
                .dateTime.day().month().year().hour().minute().locale(locale))))
        }
      }
      if loading { Text(.Details.loadingHistory).accessibilityHidden(true) }
      VStack(alignment: .leading, spacing: AppStyle.Space.small) {
        if range == .all { Text(.Details.maxExplanation) }
        Text(
          CurrencyCatalog.crypto.contains(code)
            ? .Details.cryptoExplanation : .Details.fiatExplanation)
      }
      if let message {
        Label {
          Text(message)
        } icon: {
          Image(systemName: "exclamationmark.circle")
        }
        .foregroundStyle(.primary)
      }
    }
    .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
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

/// Decorative geometry only; never supplied to Charts as historical observations.
private struct HistorySkeleton: View {
  let reduceMotion: Bool
  let axisWidth: CGFloat
  let singleDateLabel: Bool
  @State private var isVisible = false

  var body: some View {
    Chart {}
      .chartXScale(domain: 0.0...1.0).chartYScale(domain: 0.0...1.0)
      .chartYAxis {
        AxisMarks(position: .trailing, values: [0.0, 0.33, 0.66, 1.0]) { _ in
          AxisGridLine().foregroundStyle(.quaternary)
          AxisValueLabel {
            Text("0.000").font(AppStyle.font(.caption2)).hidden()
              .frame(width: axisWidth, alignment: .leading)
              .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 32, height: 8)
              }
          }
        }
      }
      .chartXAxis {
        AxisMarks(values: singleDateLabel ? [0.5] : [0.1, 0.5, 0.9]) { _ in
          AxisGridLine().foregroundStyle(.quaternary)
          AxisValueLabel {
            Text("00 Sep").font(AppStyle.font(.caption2)).hidden().fixedSize()
              .overlay {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 36, height: 8)
              }
          }
        }
      }
      .chartOverlay { proxy in
        GeometryReader { geometry in
          if let anchor = proxy.plotFrame {
            let plot = geometry[anchor]
            Path { path in
              let width = plot.width
              let height = plot.height
              path.move(to: CGPoint(x: 0, y: height * 0.55))
              path.addCurve(
                to: CGPoint(x: width * 0.5, y: height * 0.5),
                control1: CGPoint(x: width * 0.2, y: height * 0.25),
                control2: CGPoint(x: width * 0.3, y: height * 0.75))
              path.addCurve(
                to: CGPoint(x: width, y: height * 0.55),
                control1: CGPoint(x: width * 0.7, y: height * 0.25),
                control2: CGPoint(x: width * 0.8, y: height * 0.75))
            }
            .stroke(.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .offset(x: plot.minX, y: plot.minY)
          }
        }
      }
      .phaseAnimator(reduceMotion || !isVisible ? [0.7] : [0.55, 1.0]) { content, opacity in
        content.opacity(opacity)
      } animation: { _ in
        .easeInOut(duration: 1.2)
      }
      .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
      .onDisappear { isVisible = false }
      .allowsHitTesting(false)
  }
}
