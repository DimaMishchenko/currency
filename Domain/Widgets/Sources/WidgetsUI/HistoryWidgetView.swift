import Conversion
import DesignSystem
import ExchangeRates
import ExchangeRatesUI
import LocalCurrency
import SwiftUI
import WidgetKit
import Widgets

/// A historical snapshot shared by WidgetKit and the production-layout harness.
public struct HistoryWidgetEntry: TimelineEntry {
  /// Timeline activation date, distinct from the rate observation date.
  public let date: Date
  /// Historical values and availability state.
  public let snapshot: HistoryWidgetSnapshot

  /// Permission state used by the shared Local setup presentation.
  public let locationStatus: WidgetLocationStatus

  /// Creates an entry from an explicitly supplied history snapshot.
  public init(
    date: Date, snapshot: HistoryWidgetSnapshot,
    locationStatus: WidgetLocationStatus = .notDetermined
  ) {
    self.date = date
    self.snapshot = snapshot
    self.locationStatus = locationStatus
  }

  /// Illustrative data exclusively for the widget gallery and redacted placeholders.
  public static func preview(date: Date) -> Self {
    let values = [24.72, 24.78, 24.75, 24.85, 24.79, 24.82, 24.77, 24.90, 24.88, 25.04]
    let points = values.enumerated()
      .map { index, value in
        HistoryPoint(date: date.addingTimeInterval(Double(index - 9) * 3 * 86_400), value: value)
      }
    return Self(
      date: date,
      snapshot: HistoryWidgetSnapshot(
        pair: HistoryWidgetPair(app: ConverterState(), base: "EUR", quote: "CZK"), range: .month,
        result: HistoryResult(
          series: HistorySeries(
            points: points, source: .init(provider: .custom("Preview")), fetchedAt: date),
          issue: nil)))
  }
}

/// Two familiar currency rows over a quiet, full-bleed historical chart.
public struct HistoryWidgetView: View {
  @Environment(\.isWidgetPreview) private var preview
  @Environment(\.locale) private var locale
  private let entry: HistoryWidgetEntry
  private let family: WidgetFamily
  private var snapshot: HistoryWidgetSnapshot { entry.snapshot }
  private var compact: Bool { family == .systemSmall }

  /// Uses the same supplied entry and layout for installed widgets and previews.
  public init(entry: HistoryWidgetEntry, family: WidgetFamily) {
    self.entry = entry
    self.family = family
  }

  /// Currency rows, rate movement, and observation date over the historical graph.
  public var body: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
      currencyRow(snapshot.pair.base, value: 1, prominent: false)
      currencyRow(snapshot.pair.quote, value: snapshot.latest?.value, prominent: true)
      Spacer(minLength: AppStyle.Space.small)
      if let change = snapshot.change, let latest = snapshot.latest {
        HStack(alignment: .bottom) {
          VStack(alignment: .leading, spacing: AppStyle.Space.xxs) {
            Text(
              change,
              format: .percent.precision(.fractionLength(2))
                .sign(strategy: .always(includingZero: false))
            )
            .font(AppStyle.font(.headline)).monospacedDigit()
            .foregroundStyle(.primary)
            .modifier(HistoryLabelContrast())
            .accessibilityLabel(.WidgetPresentation.historyChange)
            .accessibilityValue(
              change.formatted(
                .percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false))
                  .locale(locale)))
            HStack(spacing: AppStyle.Space.xs) {
              if snapshot.issue == .usingCachedSeries {
                Image(systemName: "clock.arrow.circlepath")
                  .accessibilityLabel(.WidgetPresentation.historySaved)
              }
              Text(observationDate(latest.date))
            }
            .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
            .modifier(HistoryLabelContrast())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
              snapshot.issue == .usingCachedSeries
                ? Text(.WidgetPresentation.historySavedDate(observationDate(latest.date)))
                : Text(.WidgetPresentation.historyObservedDate(observationDate(latest.date))))
          }
          Spacer(minLength: AppStyle.Space.xs)
          rangeLabel
        }
      } else if snapshot.pair.needsLocalCurrency {
        LocalCurrencySetup(status: entry.locationStatus, compact: true)
      } else {
        HStack(alignment: .bottom) {
          Text(unavailableMessage)
            .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: AppStyle.Space.xs)
          rangeLabel
        }
      }
    }
    .padding(AppStyle.Space.large)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .font(AppStyle.font(.caption))
    .tint(Color(uiColor: .label))
    .dynamicTypeSize(...DynamicTypeSize.large)
    .modifier(HistoryWidgetBackground(snapshot: snapshot, preview: preview))
    .widgetURL(
      URL(
        string: snapshot.pair.needsLocalCurrency
          ? "currency://local-currency" : "currency://convert"))
  }

  private func currencyRow(_ code: String?, value: Double?, prominent: Bool) -> some View {
    HStack(spacing: compact ? AppStyle.Space.xs : AppStyle.Space.small) {
      if code == WidgetSelection.localID {
        Image(systemName: "location.fill")
          .frame(width: compact ? 16 : 20).accessibilityHidden(true)
        Text(.WidgetPresentation.localCurrencyChoice)
          .font(AppStyle.font(.caption, weight: .medium)).foregroundStyle(.secondary)
          .lineLimit(1).minimumScaleFactor(0.7)
      } else if let code {
        CurrencyIcon(code, size: compact ? 16 : 20).fixedSize().accessibilityHidden(true)
        Text(verbatim: code)
          .font(AppStyle.font(.caption, weight: .medium)).foregroundStyle(.secondary).fixedSize()
          .modifier(HistoryLabelContrast())
      } else {
        Text(verbatim: "—").foregroundStyle(.secondary)
      }
      Spacer(minLength: AppStyle.Space.xs)
      Text(value.map { rate($0) } ?? "—")
        .font(AppStyle.font(prominent ? (compact ? .title2 : .title) : .title3))
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4).allowsTightening(true)
        .layoutPriority(1)
        .modifier(HistoryLabelContrast())
    }
    .accessibilityElement(children: .combine)
  }

  private var rangeLabel: some View {
    Text(rangeTitle).font(AppStyle.font(.caption2, weight: .medium))
      .foregroundStyle(.secondary).fixedSize()
      .modifier(HistoryLabelContrast())
      .accessibilityLabel(rangeAccessibilityTitle)
  }

  private var unavailableMessage: LocalizedStringResource {
    if snapshot.pair.quote == nil { return .WidgetPresentation.historyChooseCurrency }
    if snapshot.issue == .unsupportedPair { return .WidgetPresentation.historyUnsupported }
    return .WidgetPresentation.historyUnavailable
  }

  private var rangeTitle: LocalizedStringResource {
    switch snapshot.range {
    case .week: .WidgetPresentation.historyWeek
    case .month: .WidgetPresentation.historyMonth
    case .quarter: .WidgetPresentation.historyQuarter
    case .year: .WidgetPresentation.historyYear
    case .all: .WidgetPresentation.historyAll
    }
  }

  private var rangeAccessibilityTitle: LocalizedStringResource {
    switch snapshot.range {
    case .week: .WidgetPresentation.historyWeekLong
    case .month: .WidgetPresentation.historyMonthLong
    case .quarter: .WidgetPresentation.historyQuarterLong
    case .year: .WidgetPresentation.historyYearLong
    case .all: .WidgetPresentation.historyAllLong
    }
  }

  private func rate(_ value: Double) -> String {
    // Significant digits retain useful precision for tiny fiat rates without long trailing zeros.
    value.formatted(.number.precision(.significantDigits(1...6)).locale(locale))
  }

  private func observationDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.setLocalizedDateFormatFromTemplate("dMMM")
    return formatter.string(from: date)
  }
}

private struct HistoryLabelContrast: ViewModifier {
  func body(content: Content) -> some View {
    // One low-opacity shadow keeps text crisp without outlining glyphs or currency icons.
    content.shadow(color: Color(uiColor: .systemBackground).opacity(0.45), radius: 0.75)
  }
}

private struct HistoryWidgetBackground: ViewModifier {
  let snapshot: HistoryWidgetSnapshot
  let preview: Bool

  func body(content: Content) -> some View {
    if preview {
      content.background { HistoryWidgetGraph(snapshot: snapshot) }
    } else {
      content.containerBackground(for: .widget) { HistoryWidgetGraph(snapshot: snapshot) }
    }
  }
}

private struct HistoryWidgetGraph: View {
  @Environment(\.widgetRenderingMode) private var renderingMode
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast
  let snapshot: HistoryWidgetSnapshot

  private var tint: Color {
    guard renderingMode == .fullColor, let change = snapshot.change, change != 0 else {
      return .secondary
    }
    return change > 0 ? .green : .red
  }

  var body: some View {
    ZStack {
      Color(uiColor: .systemBackground)
      if let points = snapshot.series?.points, let first = points.first, let last = points.last {
        Canvas { context, size in
          let low = points.map(\.value).min() ?? 0
          let high = points.map(\.value).max() ?? 1
          let spread = max(high - low, high * 0.002)
          let midpoint = (high + low) / 2
          let duration = last.date.timeIntervalSince(first.date)
          var line = Path()
          for (index, point) in points.enumerated() {
            let x = point.date.timeIntervalSince(first.date) / duration * size.width
            let y = size.height * (0.50 - (point.value - midpoint) / spread * 0.76)
            let position = CGPoint(x: x, y: y)
            if index == 0 { line.move(to: position) } else { line.addLine(to: position) }
          }
          var area = line
          area.addLine(to: CGPoint(x: size.width, y: size.height))
          area.addLine(to: CGPoint(x: 0, y: size.height))
          area.closeSubpath()
          context.fill(
            area,
            with: .linearGradient(
              Gradient(colors: [
                tint.opacity(colorScheme == .dark ? 0.22 : 0.17), tint.opacity(0.025)
              ]),
              startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
          context.stroke(
            line, with: .color(tint.opacity(contrast == .increased ? 0.85 : 0.6)),
            style: StrokeStyle(lineWidth: contrast == .increased ? 2 : 1.5, lineJoin: .round))
        }
      }
    }
    .accessibilityHidden(true)
  }
}
