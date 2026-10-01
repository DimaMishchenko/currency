import Charts
import CurrencyDetails
import DesignSystem
import ExchangeRates
import ExchangeRatesUI
import SwiftUI

struct RateDetailsScreen: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.locale) private var locale
  @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 48
  @ScaledMetric(relativeTo: .title2) private var titleBaselineOffset =
    (UIFont.systemFont(ofSize: 22).ascender + UIFont.systemFont(ofSize: 22).descender) / 2
  @ScaledMetric(relativeTo: .caption2) private var scaledAxisWidth = 44
  private var axisWidth: CGFloat { min(scaledAxisWidth, 64) }
  private let axisLabelSpacing: CGFloat = 4
  @Bindable var model: CurrencyDetailsModel
  private var code: String { model.input.code }
  private var reference: String { model.input.reference }
  private var snapshot: RateSnapshot { model.input.snapshot }
  @Environment(\.dismiss) private var dismiss
  private var range: HistoryRange { model.range }
  private var series: HistorySeries? { model.series }
  private var message: LocalizedStringResource? { RateMessages.history(model.issue) }
  private var loading: Bool { model.phase != .loaded }
  @State private var reveal: CGFloat = 0
  private var currencyName: String { CurrencyDisplay.name(code, locale: locale) }

  @State private var selectedDate: Date?
  private var quote: String { model.quote }

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

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: AppStyle.Space.section) {
          VStack(alignment: .leading, spacing: AppStyle.Space.small) {
            Text(.Details.unitConversion(code, quote))
              .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
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
            Picker(.Details.historyRange, selection: $model.range) {
              ForEach(model.availableRanges, id: \.self) { range in
                Text(range.title).accessibilityLabel(range.accessibilityTitle).tag(range)
              }
            }
            .pickerStyle(.segmented)
            historyContent
            historyFooter
          }
        }
        .padding(AppStyle.Space.large)
      }
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .top, spacing: 0) {
        HStack(alignment: .firstTextBaseline, spacing: AppStyle.Space.medium) {
          HStack(alignment: .firstTextBaseline, spacing: AppStyle.Space.medium) {
            CurrencyIcon(code, size: 36).accessibilityHidden(true)
              .alignmentGuide(.firstTextBaseline) { $0.height / 2 }
            Text(currencyName)
              .font(AppStyle.font(.title2, weight: .semibold))
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .alignmentGuide(.firstTextBaseline) {
                $0[.firstTextBaseline] - titleBaselineOffset
              }
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(currencyName)
          .accessibilityAddTraits(.isHeader)
          Button(.Details.close, systemImage: "xmark") {
            AppHaptics.play(.action); dismiss()
          }
          .labelStyle(.iconOnly)
          .accessibilityIdentifier("currency.details.close")
          .font(AppStyle.font(.title2))
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
          .frame(width: 44, height: 44)
          .buttonStyle(.glass)
          .buttonBorderShape(.circle)
          .tint(nil)
          .alignmentGuide(.firstTextBaseline) { $0.height / 2 }
        }
        .padding(.horizontal, AppStyle.Space.large)
        .padding(.vertical, AppStyle.Space.small)
        .background(.background)
      }
      .onChange(of: range) { _, _ in AppHaptics.play(.selection) }
      .onChange(of: selected?.date) { _, _ in
        if selectedDate != nil && !loading { AppHaptics.play(.selection) }
      }
      .onDisappear { AppHaptics.stop(.chartReveal) }
      .task(id: range) {
        reveal = 0
        selectedDate = nil
        await model.load()
        guard !Task.isCancelled else { return }
        if model.issue != nil { AppHaptics.play(.warning) }
        guard model.series?.points.isEmpty == false else { return }
        if reduceMotion {
          reveal = 1
        } else {
          await Task.yield()
          guard !Task.isCancelled else { return }
          if model.issue == nil { AppHaptics.play(.chartReveal) }
          withAnimation(.easeOut(duration: 0.55)) { reveal = 1 }
        }
      }
    }
  }

  private var historyContent: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.medium) {
      ZStack(alignment: .leading) {
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
            reduceMotion: reduceMotion, axisWidth: axisWidth, axisLabelSpacing: axisLabelSpacing,
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
            description: Text(
              model.issue == .intradayUnavailable
                ? .Details.intradayExplanation : .Details.tryAnotherRange)
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
      .opacity(0)
      if selectedDate != nil, selected?.id == point.id {
        RuleMark(x: .value(String(localized: .Details.chartDate), point.date))
          .foregroundStyle(.secondary.opacity(0.3))
        PointMark(
          x: .value(String(localized: .Details.chartDate), point.date),
          y: .value(quote, point.value)
        )
        .foregroundStyle(.tint)
      }
    }
    .chartYScale(domain: domain)
    .chartXSelection(value: $selectedDate)
    .chartYAxis {
      AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine()
        AxisValueLabel(horizontalSpacing: axisLabelSpacing) {
          if let number = value.as(Double.self) {
            Text(
              number.formatted(
                .number.notation(dynamicTypeSize.isAccessibilitySize ? .scientific : .automatic)
                  .precision(.significantDigits(1...4)).locale(locale))
            )
            .font(AppStyle.font(.caption2)).lineLimit(1).minimumScaleFactor(0.7)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(
              width: dynamicTypeSize.isAccessibilitySize ? axisWidth : nil, alignment: .leading)
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
          Path { path in
            for (index, point) in series.points.enumerated() {
              if let x = proxy.position(forX: point.date), let y = proxy.position(forY: point.value)
              {
                let position = CGPoint(x: x, y: y)
                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
              }
            }
          }
          .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
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
        Text(date.formatted(historyAxisFormat))
          .font(AppStyle.font(.caption2)).fixedSize()
      }
    }
  }

  private var historyAxisFormat: Date.FormatStyle {
    var format: Date.FormatStyle =
      switch range {
      case .day: .dateTime.hour().minute()
      case .all: .dateTime.year()
      default: .dateTime.day().month(.abbreviated)
      }
    format.locale = locale
    format.timeZone = .gmt
    return format
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
      if let message, model.issue != .intradayUnavailable {
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
    formatter.timeStyle = range == .day ? .short : .none
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }
}

private struct HistorySkeleton: View {
  let reduceMotion: Bool
  let axisWidth: CGFloat
  let axisLabelSpacing: CGFloat
  let singleDateLabel: Bool
  @State private var isVisible = false

  var body: some View {
    Chart {
      ChartContentBuilder.buildBlock()
    }
    .chartXScale(domain: 0.0...1.0).chartYScale(domain: 0.0...1.0)
    .chartYAxis {
      AxisMarks(position: .trailing, values: [0.0, 0.33, 0.66, 1.0]) { _ in
        AxisGridLine().foregroundStyle(.quaternary)
        AxisValueLabel(horizontalSpacing: axisLabelSpacing) {
          Text(verbatim: "0.000").font(AppStyle.font(.caption2)).hidden()
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
          Text(verbatim: "00 Sep").font(AppStyle.font(.caption2)).hidden().fixedSize()
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
