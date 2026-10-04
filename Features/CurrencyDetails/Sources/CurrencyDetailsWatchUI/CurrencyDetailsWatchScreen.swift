import Charts
import CurrencyDetails
import ExchangeRates
import ExchangeRatesUI
import SwiftUI

/// Watch rate provenance and history presentation for one immutable details flow.
public struct CurrencyDetailsWatchScreen: View {
  @State private var model: CurrencyDetailsModel
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Supplies the selected pair, rate snapshot, and owned history loading capability.
  public init(input: CurrencyDetailsInput, dependencies: CurrencyDetailsDependencies) {
    _model = State(initialValue: CurrencyDetailsModel(input: input, dependencies: dependencies))
  }

  /// Shows provider history and disclosures for the captured pair, including cached or unavailable results.
  public var body: some View {
    @Bindable var model = model
    List {
      Section {
        HStack(alignment: .top, spacing: 8) {
          CurrencyIcon(model.input.code, size: 28)
          Text(verbatim: CurrencyDisplay.name(model.input.code, locale: locale))
            .font(.system(.headline, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
        }
        Text(
          verbatim:
            "\(amountLabel("1", code: model.input.code)) = \(amountLabel(rate, code: model.quote))"
        )
        .font(.system(.body, design: .rounded, weight: .medium))
        .monospacedDigit().fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("watch.details.rate")
      }
      Section {
        Picker(selection: $model.range) {
          ForEach(model.availableRanges, id: \.self) { range in
            Text(title(range)).tag(range)
          }
        } label: {
          Text(.Watch.historyRange)
        }
        .accessibilityIdentifier("watch.details.range")
        if model.phase == .loading || model.phase == .idle {
          ProgressView().accessibilityLabel(Text(.Watch.loadingHistory))
        } else if let series = model.series, !series.points.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(verbatim: "\(model.input.code) → \(model.quote)")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
              Spacer(minLength: 4)
              Text(title(model.range)).font(.caption2).foregroundStyle(.secondary)
            }
            if let latest = series.points.last {
              Text(
                verbatim:
                  amountLabel(
                    latest.value.formatted(
                      .number.precision(.significantDigits(1...6)).locale(locale)),
                    code: model.quote)
              )
              .font(.system(.body, design: .rounded, weight: .medium))
              .monospacedDigit()
              .fixedSize(horizontal: false, vertical: true)
              .contentTransition(reduceMotion ? .identity : .numericText())
              .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: latest.value)
            }
            Chart(series.points) { point in
              LineMark(
                x: .value(String(localized: .Watch.historyTitle), point.date),
                y: .value(model.quote, point.value))
            }
            .chartYScale(domain: chartDomain(series))
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) }
            .frame(height: 64)
            .accessibilityLabel(Text(.Watch.historyTitle))
            .accessibilityValue(Text(verbatim: "\(model.input.code) → \(model.quote)"))
            .accessibilityIdentifier("watch.details.chart")
            if let first = series.points.first, let latest = series.points.last {
              HStack {
                Text(verbatim: chartDate(first.date))
                Spacer(minLength: 4)
                Text(verbatim: chartDate(latest.date))
              }
              .font(.caption2).foregroundStyle(.secondary)
              .lineLimit(1).minimumScaleFactor(0.8)
              .accessibilityElement(children: .combine)
            }
          }
          .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        } else {
          Text(.Watch.noHistory).fixedSize(horizontal: false, vertical: true)
        }
        if let issue = model.issue {
          Text(message(issue)).font(.caption2).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("watch.details.issue")
        }
      } header: {
        Text(.Watch.historyTitle)
      }
      Section {
        if let quote = model.input.snapshot.quotes[model.input.code] {
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: provider(quote.source.provider))
              .font(.system(.headline, design: .rounded))
            Text(observation(quote.source.observation)).font(.caption2)
            Text(verbatim: quote.published).font(.caption2)
            if let date = quote.observedAt ?? quote.retrievedAt ?? quote.cachedAt {
              Text(date, format: .dateTime.month().day().hour().minute())
                .font(.caption2).foregroundStyle(.secondary)
            }
          }
          .accessibilityElement(children: .combine)
        } else {
          Text(.Watch.rateUnavailable)
        }
        if let series = model.series {
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: provider(series.source.provider))
              .font(.system(.headline, design: .rounded))
            Text(observation(series.source.observation)).font(.caption2)
            Text(.Watch.historySaved).font(.caption2)
            Text(series.fetchedAt, format: .dateTime.month().day().hour().minute())
              .font(.caption2).foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
        }
        Text(.Watch.referenceExplanation).font(.caption2)
      } header: {
        Text(.Watch.sourceTitle)
      }
    }
    .font(.system(.body, design: .rounded))
    .navigationTitle(model.input.code)
    .task(id: model.range) { await model.load() }
    .onDisappear { model.stop() }
  }

  private func amountLabel(_ amount: String, code: String) -> String {
    if CurrencyCatalog.metals.contains(code) {
      var resource = LocalizedStringResource.Watch.metalAmount(amount, code)
      resource.locale = locale
      return String(localized: resource)
    }
    return "\(amount) \(code)"
  }

  private var rate: String {
    guard let value = model.input.snapshot.convert(1, from: model.input.code, to: model.quote)
    else {
      return "—"
    }
    return value.formatted(.number.precision(.significantDigits(1...6)).locale(locale))
  }

  private func chartDate(_ date: Date) -> String {
    let format: Date.FormatStyle =
      model.range == .all
      ? .dateTime.month(.abbreviated).year() : .dateTime.month(.abbreviated).day()
    return date.formatted(format.locale(locale))
  }

  private func chartDomain(_ series: HistorySeries) -> ClosedRange<Double> {
    let values = series.points.map(\.value)
    let minimum = values.min() ?? 0
    let maximum = values.max() ?? 1
    let padding = max((maximum - minimum) * 0.1, max(abs(maximum) * 0.001, 0.00000001))
    return max(0, minimum - padding)...(maximum + padding)
  }

  private func title(_ range: HistoryRange) -> LocalizedStringResource {
    switch range {
    case .day: .Watch.day
    case .week: .Watch.week
    case .month: .Watch.month
    case .quarter: .Watch.quarter
    case .yearToDate: .Watch.yearToDate
    case .year: .Watch.year
    case .all: .Watch.all
    }
  }

  private func message(_ issue: HistoryIssue) -> LocalizedStringResource {
    switch issue {
    case .unsupportedPair: .Watch.unsupportedPair
    case .intradayUnavailable: .Watch.intradayUnavailable
    case .unavailable: .Watch.historyUnavailable
    case .usingCachedSeries: .Watch.cachedHistory
    case .cacheWriteFailed: .Watch.historySaveFailed
    }
  }

  private func provider(_ id: RateProviderID) -> String {
    switch id {
    case .ecb: "European Central Bank"
    case .frankfurter: "Frankfurter"
    case .fawaz: "Fawaz"
    case .coinbase: "Coinbase"
    case .custom(let name): name
    }
  }

  private func observation(_ observation: RateObservation) -> LocalizedStringResource {
    switch observation {
    case .unspecified: .Watch.unspecifiedObservation
    case .dailyRate: .Watch.dailyRate
    case .exchangeRate: .Watch.exchangeRate
    case .trade: .Watch.trade
    case .dailyReference: .Watch.dailyReference
    case .monthlyReference: .Watch.monthlyReference
    case .hourlyClose: .Watch.hourlyClose
    case .dailyClose: .Watch.dailyClose
    case .monthlyLastClose: .Watch.monthlyLastClose
    }
  }
}
