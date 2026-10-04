import Charts
import ExchangeRates
import ExchangeRatesUI
import Foundation
import SwiftUI
import WidgetKit
import Widgets

struct WatchRateView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.widgetRenderingMode) private var renderingMode
  @Environment(\.locale) private var locale
  let entry: WatchWidgetEntry

  private var quote: String { entry.activeQuote ?? "" }
  private var amount: Decimal {
    if entry.style == .cash {
      let presets = WidgetPresets.amounts(entry.activeSource)
      return presets.contains(entry.input.decimal) ? entry.input.decimal : presets[0]
    }
    return entry.input.decimal
  }
  private var value: Decimal? {
    guard entry.snapshot.hasValidFetchTimestamp(now: entry.date), !quote.isEmpty else { return nil }
    if entry.style == .cash {
      guard WidgetPresets.allows(entry.activeSource), WidgetPresets.allows(quote) else {
        return nil
      }
      return WidgetPresets.convert(
        amount, from: entry.activeSource, to: quote, snapshot: entry.snapshot)
    }
    return entry.value(to: quote)
  }
  private var displayValue: String {
    format(value, code: quote)
      + unit(for: quote)
  }
  private var pair: String { entry.activeSource + " → " + quote }
  private var rule: (divide: Bool, factor: Decimal, error: Decimal)? {
    guard let value = entry.snapshot.convert(1, from: entry.activeSource, to: quote),
      entry.snapshot.hasValidFetchTimestamp(now: entry.date)
    else { return nil }
    return WidgetMath.rule(rate: value)
  }
  private var primary: String {
    if entry.style == .mental, let rule {
      return (rule.divide ? "÷ " : "× ") + format(rule.factor, code: "")
    }
    return displayValue
  }

  var body: some View {
    Group {
      if entry.style == .cash
        && (!WidgetPresets.allows(entry.activeSource) || !WidgetPresets.allows(quote)
          || entry.activeSource == quote)
      {
        Text(.WatchWidgets.chooseCashPair)
      } else if !entry.configurationIsValid {
        Text(.WatchWidgets.invalidAmount)
      } else {
        switch family {
        case .accessoryInline:
          if entry.style == .mental {
            Text(verbatim: pair + " " + primary)
          } else {
            Text(verbatim: amountText + " ≈ " + displayValue + " " + quote)
          }
        case .accessoryCorner:
          Text(verbatim: primary)
            .font(.title3).minimumScaleFactor(0.4)
            .accessibilityLabel(
              Text(
                verbatim: entry.style == .mental
                  ? pair + " " + primary : amountText + " → " + displayValue + " " + quote)
            )
            .widgetLabel {
              Text(
                verbatim: entry.style == .mental
                  ? pair : amountText + " → " + quote + unit(for: quote)
              )
              .lineLimit(1).minimumScaleFactor(0.5)
            }
        case .accessoryCircular:
          VStack(spacing: 1) {
            Text(verbatim: entry.style == .mental ? entry.activeSource : quote).font(.caption2)
            Text(verbatim: primary).font(.headline).minimumScaleFactor(0.35)
            if entry.style != .mental { Text(verbatim: amountText).font(.caption2) }
          }
          .lineLimit(1).containerBackground(.fill.tertiary, for: .widget)
        default:
          rectangular
        }
      }
    }
    .fontDesign(.rounded)
    .widgetURL(conversionURL)
    .accessibilityElement(children: family == .accessoryRectangular ? .contain : .combine)
  }

  private var conversionURL: URL {
    guard entry.style == .cash else { return entry.url() }
    let sourceAmount =
      WidgetPresets.metals.contains(entry.activeSource)
      ? amount / WidgetPresets.gramsPerTroyOunce : amount
    var rawAmount = sourceAmount
    var roundedAmount = Decimal()
    NSDecimalRound(&roundedAmount, &rawAmount, 12, .plain)
    return WatchWidgetRoute.url(
      source: entry.activeSource, quote: entry.activeQuote,
      amount: NSDecimalNumber(decimal: roundedAmount).stringValue)
  }

  private var amountText: String {
    format(amount, code: entry.activeSource) + " " + entry.activeSource
      + unit(for: entry.activeSource)
  }
  private func unit(for code: String) -> String {
    guard WidgetPresets.metals.contains(code) else { return "" }
    return entry.style == .cash ? " g" : " " + String(localized: .WatchWidgets.troyOunce)
  }

  private var rectangular: some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 3) {
        CurrencyIcon(entry.activeSource, size: 11).frame(width: 13, height: 11)
        Text(verbatim: pair).font(.system(size: 10, weight: .semibold))
        Spacer(minLength: 0)
        if entry.style != .cash && entry.style != .mental {
          Button(intent: WatchWidgetSwapIntent(entry: entry)) {
            Image(systemName: "arrow.up.arrow.down")
              .font(.system(size: 10, weight: .semibold))
              .frame(width: 18, height: 12).contentShape(Rectangle())
          }
          .buttonStyle(.plain).accessibilityLabel(Text(.WatchWidgets.swap))
          .disabled(value == nil)
        }
      }
      .frame(height: 12)
      if entry.style == .cash {
        cashRows
        WatchRateFreshness(entry: entry).frame(height: 10)
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          if entry.style != .mental {
            Text(verbatim: format(amount, code: entry.activeSource) + unit(for: entry.activeSource))
              .font(.system(size: 11))
            Image(systemName: "equal").font(.system(size: 8))
          }
          Text(verbatim: primary).font(.system(size: 16, weight: .semibold))
          Spacer(minLength: 0)
          if entry.style == .mental, let rule {
            Text(
              .WatchWidgets.approximationError(
                rule.error.formatted(.percent.precision(.fractionLength(1))))
            )
            .font(.system(size: 9)).foregroundStyle(.secondary)
          }
        }
        .frame(height: 19)
        HStack(spacing: 4) {
          if entry.style != .mental && renderingMode == .fullColor { presetButtons }
          WatchRateFreshness(entry: entry)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 18)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .lineLimit(1).minimumScaleFactor(0.5).monospacedDigit()
    .containerBackground(.fill.tertiary, for: .widget)
  }

  private var presetButtons: some View {
    HStack(spacing: 3) {
      ForEach([Decimal(1), 10, 100], id: \.self) { value in
        Button(intent: WatchWidgetPresetIntent(entry: entry, amount: value)) {
          Text(verbatim: value.description).font(.system(size: 9, weight: .semibold))
            .frame(width: value == 100 ? 25 : 21, height: 18)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.WatchWidgets.useAmount(value.description)))
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  private var cashRows: some View {
    VStack(spacing: 0) {
      ForEach(WidgetPresets.amounts(entry.activeSource), id: \.self) { preset in
        let result =
          entry.snapshot.hasValidFetchTimestamp(now: entry.date)
            && WidgetPresets.allows(entry.activeSource) && WidgetPresets.allows(quote)
          ? WidgetPresets.convert(
            preset, from: entry.activeSource, to: quote, snapshot: entry.snapshot) : nil
        HStack {
          Text(
            verbatim: format(preset, code: entry.activeSource)
              + (WidgetPresets.metals.contains(entry.activeSource) ? " g" : ""))
          Spacer(minLength: 2)
          Text(
            verbatim: "≈ " + format(result, code: quote)
              + (WidgetPresets.metals.contains(quote) ? " g" : ""))
        }
        .font(.system(size: 10)).monospacedDigit().frame(height: 10)
      }
    }
    .accessibilityLabel(
      Text(
        WidgetPresets.metals.contains(entry.activeSource)
          ? .WatchWidgets.grams
          : WidgetPresets.isBanknote(entry.activeSource)
            ? .WatchWidgets.banknotes
            : .WatchWidgets.referenceAmounts))
  }

  private func format(_ value: Decimal?, code: String) -> String {
    WatchWidgetFormat.amount(value, code: code, locale: locale)
  }
}

struct WatchBoardView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.locale) private var locale
  let entry: WatchWidgetEntry

  var body: some View {
    if !entry.configurationIsValid {
      Text(.WatchWidgets.invalidAmount)
    } else if entry.style == .favorites && family == .accessoryRectangular {
      favorites
    } else if family == .accessoryRectangular {
      VStack(alignment: .leading, spacing: 0) {
        Text(
          verbatim: entry.input.amount + " " + entry.activeSource
            + WatchWidgetFormat.unit(entry.activeSource)
        )
        .font(.system(size: 10, weight: .semibold)).frame(height: 12)
        if entry.targets.isEmpty { Text(.WatchWidgets.addFavorites).font(.system(size: 10)) }
        ForEach(Array(entry.targets.prefix(3)), id: \.self) {
          code in
          HStack(spacing: 3) {
            CurrencyIcon(code, size: 9).frame(width: 11, height: 10)
            Text(verbatim: code)
            Spacer(minLength: 2)
            Text(
              verbatim: WatchWidgetFormat.amount(entry.value(to: code), code: code, locale: locale)
                + WatchWidgetFormat.unit(code))
          }
          .font(.system(size: 10)).monospacedDigit().frame(height: 10)
        }
        WatchRateFreshness(entry: entry).frame(height: 10)
      }
      .fontDesign(.rounded)
      .lineLimit(1).minimumScaleFactor(0.55)
      .widgetURL(entry.url())
      .containerBackground(.fill.tertiary, for: .widget)
    } else {
      WatchRateView(entry: entry)
    }
  }

  private func localized(_ resource: LocalizedStringResource) -> String {
    var resource = resource
    resource.locale = locale
    return String(localized: resource)
  }

  private var sourceAmount: String {
    WatchWidgetFormat.amount(entry.input.decimal, code: entry.activeSource, locale: locale)
      + " " + entry.activeSource + WatchWidgetFormat.unit(entry.activeSource)
  }

  private var savedRateStatus: String {
    guard entry.evaluation?.refreshFailed == true || entry.evaluation?.cacheIsStale == true else {
      return ""
    }
    let date = entry.snapshot.fetchedAt.formatted(
      .dateTime.locale(locale).day().month(.abbreviated).hour().minute())
    return localized(.WatchWidgets.savedRatesAsOf(date))
  }

  private var favorites: some View {
    AccessoryWidgetGroup {
      HStack(spacing: 3) {
        Text(verbatim: sourceAmount).font(.system(size: 10)).monospacedDigit()
        if !savedRateStatus.isEmpty {
          Image(systemName: "clock.arrow.circlepath").font(.system(size: 9))
            .accessibilityLabel(Text(verbatim: savedRateStatus))
        }
      }
      .lineLimit(1).minimumScaleFactor(0.6)
    } content: {
      ForEach(Array(entry.targets.prefix(3)), id: \.self) { code in
        Link(destination: entry.url(quote: code)) {
          VStack(spacing: 1) {
            Text(verbatim: code).font(.system(size: 9))
            Text(
              verbatim: WatchWidgetFormat.amount(entry.value(to: code), code: code, locale: locale)
                + WatchWidgetFormat.unit(code)
            )
            .font(.system(size: 10)).minimumScaleFactor(0.4)
          }
          .lineLimit(1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          Text(
            verbatim: sourceAmount + " → "
              + WatchWidgetFormat.amount(entry.value(to: code), code: code, locale: locale)
              + " " + code + WatchWidgetFormat.unit(code))
        )
        .accessibilityHint(Text(verbatim: savedRateStatus))
      }
      if entry.targets.isEmpty {
        Link(destination: WatchWidgetRoute.url()) { Image(systemName: "plus") }
          .accessibilityLabel(Text(.WatchWidgets.addFavorites))
      }
    }
    .fontDesign(.rounded)
    .accessoryWidgetGroupStyle(.roundedSquare)
    .widgetURL(entry.url())
    .containerBackground(.fill.tertiary, for: .widget)
  }
}

struct WatchRateFreshness: View {
  let entry: WatchWidgetEntry
  var body: some View {
    Group {
      if entry.evaluation == nil
        || entry.evaluation?.results.allSatisfy({ $0.amount == nil }) == true
      {
        Text(.WatchWidgets.ratesUnavailable)
      } else if entry.evaluation?.refreshFailed == true || entry.evaluation?.cacheIsStale == true {
        Text(
          .WatchWidgets.savedRatesAsOf(
            entry.snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)))
      } else if entry.evaluation?.dailyFallback == true {
        Text(.WatchWidgets.dailyRate)
      } else if entry.evaluation?.fetchedAt != nil {
        Text(
          .WatchWidgets.updated(
            entry.snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)))
      }
    }
    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
  }
}

struct WatchHistoryView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.locale) private var locale
  let entry: WatchHistoryEntry
  private var snapshot: HistoryWidgetSnapshot { entry.snapshot }
  private var pair: String { snapshot.pair.base + " → " + (snapshot.pair.quote ?? "") }
  private var latest: String {
    snapshot.latest.map {
      WatchWidgetFormat.amount(Decimal($0.value), code: snapshot.pair.quote ?? "", locale: locale)
        + WatchWidgetFormat.unit(snapshot.pair.quote ?? "")
    } ?? "—"
  }
  private var change: String {
    snapshot.change?
      .formatted(
        .percent.locale(locale).precision(.fractionLength(2)).sign(strategy: .always()))
      ?? "—"
  }
  private func localized(_ resource: LocalizedStringResource) -> String {
    var resource = resource
    resource.locale = locale
    return String(localized: resource)
  }

  private var rangeTitle: LocalizedStringResource {
    switch snapshot.range {
    case .day: .WatchWidgets.historyDay
    case .week: .WatchWidgets.historyWeek
    case .month: .WatchWidgets.historyMonth
    case .quarter: .WatchWidgets.historyQuarter
    case .year: .WatchWidgets.historyYear
    case .yearToDate: .WatchWidgets.historyYearToDate
    case .all: .WatchWidgets.historyAll
    }
  }
  private var rangeAccessibilityTitle: LocalizedStringResource {
    switch snapshot.range {
    case .day: .WatchWidgets.day
    case .week: .WatchWidgets.week
    case .month: .WatchWidgets.month
    case .quarter: .WatchWidgets.quarter
    case .year: .WatchWidgets.year
    case .yearToDate: .WatchWidgets.historyYearToDateLong
    case .all: .WatchWidgets.all
    }
  }
  private var periodChange: String {
    localized(rangeTitle) + " " + change
  }
  private var accessibilitySummary: String {
    let date =
      snapshot.latest?.date
      .formatted(
        .dateTime.locale(locale).day().month(.abbreviated).year()) ?? ""
    return pair + ", " + localized(rangeAccessibilityTitle)
      + ", " + change + ", " + latest + " " + date
      + ", "
      + localized(snapshot.series == nil ? .WatchWidgets.historyUnavailable : provenance)
  }
  private var provenance: LocalizedStringResource {
    if snapshot.issue == .usingCachedSeries { return .WatchWidgets.savedHistory }
    switch snapshot.series?.source.observation {
    case .hourlyClose: return .WatchWidgets.hourlyCloses
    case .dailyClose: return .WatchWidgets.dailyCloses
    case .monthlyLastClose: return .WatchWidgets.monthlyCloses
    case .monthlyReference: return .WatchWidgets.monthlyReference
    default: return .WatchWidgets.referenceHistory
    }
  }
  var body: some View {
    Group {
      switch family {
      case .accessoryInline: Text(verbatim: pair + " " + periodChange)
      case .accessoryCorner:
        Text(verbatim: change).font(.title3).minimumScaleFactor(0.4)
          .widgetLabel {
            Text(verbatim: pair + " " + localized(rangeTitle))
          }
      case .accessoryCircular:
        VStack(spacing: 2) {
          Text(verbatim: snapshot.pair.base + "→" + (snapshot.pair.quote ?? ""))
            .font(.system(size: 9, weight: .medium))
          Text(verbatim: periodChange).font(.system(size: 12, weight: .semibold))
        }
        .minimumScaleFactor(0.45)
        .containerBackground(.fill.tertiary, for: .widget)
      default:
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 3) {
            CurrencyIcon(snapshot.pair.base, size: 10).frame(width: 12, height: 11)
            Text(verbatim: pair).font(.system(size: 10, weight: .semibold))
            Spacer(minLength: 0)
            Text(verbatim: periodChange).font(.system(size: 9))
          }
          .frame(height: 12)
          if let series = snapshot.series {
            Chart(series.points) { point in
              LineMark(
                x: .value(String(localized: .WatchWidgets.date), point.date),
                y: .value(String(localized: .WatchWidgets.rate), point.value))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 17)
            .accessibilityLabel(Text(.WatchWidgets.historyChart(pair)))
            HStack {
              Text(verbatim: latest)
              Spacer(minLength: 0)
              Text(
                verbatim: snapshot.latest?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
            }
            .font(.system(size: 9)).frame(height: 10)
            Text(provenance).font(.system(size: 9)).foregroundStyle(.secondary).frame(height: 10)
          } else {
            Text(.WatchWidgets.historyUnavailable).font(.system(size: 11))
          }
        }
        .containerBackground(.fill.tertiary, for: .widget)
      }
    }
    .fontDesign(.rounded)
    .lineLimit(1).minimumScaleFactor(0.5).monospacedDigit()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: accessibilitySummary))
    .widgetURL(
      WatchWidgetRoute.url(source: snapshot.pair.base, quote: snapshot.pair.quote, details: true))
  }
}

struct WatchIconView: View {
  @Environment(\.widgetFamily) private var family
  let entry: WatchIconEntry
  var body: some View {
    Group {
      if family == .accessoryInline {
        Label {
          Text(.WatchWidgets.openCurrency)
        } icon: {
          icon(size: 11)
        }
      } else {
        icon(size: 26).widgetAccentable()
          .widgetLabel { Text(.WatchWidgets.openCurrency) }
      }
    }
    .fontDesign(.rounded)
    .widgetURL(WatchWidgetRoute.url())
    .containerBackground(.fill.tertiary, for: .widget)
    .accessibilityLabel(Text(.WatchWidgets.openCurrency))
  }

  @ViewBuilder private func icon(size: CGFloat) -> some View {
    if let code = Self.currencyCodes[entry.symbol] {
      CurrencyIcon(code, size: size)
    } else {
      Image(systemName: entry.symbol.id).font(.system(size: size, design: .rounded))
    }
  }

  private static let currencyCodes: [CurrencySymbol: String] = [
    .australiandollar: "AUD", .baht: "THB", .bitcoin: "BTC", .brazilianreal: "BRL",
    .cedi: "GHS", .chineseyuanrenminbi: "CNY", .danishkrone: "DKK", .dong: "VND",
    .dollar: "USD", .euro: "EUR", .eurozone: "EUR", .franc: "CHF", .guarani: "PYG",
    .hryvnia: "UAH", .indianrupee: "INR", .kip: "LAK", .lari: "GEL", .lira: "TRY",
    .malaysianringgit: "MYR", .manat: "AZN", .naira: "NGN", .norwegiankrone: "NOK",
    .peruviansoles: "PEN", .peso: "PHP", .polishzloty: "PLN", .ruble: "RUB",
    .rupee: "INR", .shekel: "ILS", .singaporedollar: "SGD", .sterling: "GBP",
    .swedishkrona: "SEK", .tenge: "KZT", .tugrik: "MNT", .turkishlira: "TRY",
    .won: "KRW", .yen: "JPY"
  ]
}

enum WatchWidgetFormat {
  static func unit(_ code: String) -> String {
    WidgetPresets.metals.contains(code) ? " " + String(localized: .WatchWidgets.troyOunce) : ""
  }
  static func amount(_ value: Decimal?, code: String, locale: Locale) -> String {
    guard let value, !value.isNaN else { return "—" }
    let digits = CurrencyPrecision.fractionDigits(code)
    let step = pow(Decimal(10), -digits)
    if value != 0 && abs(value) < step {
      return value.formatted(.number.locale(locale).precision(.significantDigits(3...6)))
    }
    return value.formatted(.number.locale(locale).precision(.fractionLength(0...digits)))
  }
}
