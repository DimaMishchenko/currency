import CurrencyDetails
import CurrencyDetailsUI
import DesignSystem
import ExchangeRates
import SwiftUI

@main
struct CurrencyDetailsHarnessApp: App {
  @State private var flowID = UUID()
  @State private var appearance = AppAppearance(
    theme: .system, accent: .primary, onThemeChange: { _ in }, onAccentChange: { _ in })

  private var name: String {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "--case"), arguments.indices.contains(index + 1)
    else { return "normal" }
    return arguments[index + 1]
  }

  private var code: String {
    switch name {
    case "crypto": "BTC"
    case "long-name": "BAM"
    default: "EUR"
    }
  }

  private var snapshot: RateSnapshot {
    RateSnapshot(
      quotes: [
        "BAM": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .ecb)),
        "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .ecb)),
        "USD": ExchangeRate(1.08, published: "2026-09-19", source: .init(provider: .ecb)),
        "BTC": ExchangeRate(0.000018, published: "2026-09-19", source: .init(provider: .coinbase))
      ], fetchedAt: .now)
  }

  private var dependencies: CurrencyDetailsDependencies {
    .init { _, _, range in
      if name == "loading" || name == "interrupted" {
        do { try await Task.sleep(for: .seconds(30)) } catch {
          return HistoryResult(series: nil, issue: nil)
        }
      }
      if name == "empty" { return HistoryResult(series: nil, issue: .unsupportedPair) }
      if name == "failure" { return HistoryResult(series: nil, issue: .unavailable) }
      if range == .day && code != "BTC" {
        return HistoryResult(series: nil, issue: .intradayUnavailable)
      }
      let count: Int
      let interval: TimeInterval
      switch range {
      case .day: count = 24; interval = 3600
      case .week: count = 7; interval = 86_400
      case .month: count = 30; interval = 86_400
      case .quarter: count = 90; interval = 86_400
      case .year: count = 365; interval = 86_400
      case .yearToDate:
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let start = calendar.dateInterval(of: .year, for: .now)?.start ?? .now
        count = max(0, calendar.dateComponents([.day], from: start, to: .now).day ?? 0)
        interval = 86_400
      case .all: count = 120; interval = 30 * 86_400
      }
      let isCrypto = code == "BTC"
      let points = (0..<count)
        .map {
          HistoryPoint(
            date: Date.now.addingTimeInterval(Double($0 - count) * interval),
            value: isCrypto
              ? 60_000 + sin(Double($0) / 4) * 1200 : 1.08 + sin(Double($0) / 4) * 0.03)
        }
      return HistoryResult(
        series: HistorySeries(
          points: points,
          source: .init(
            provider: isCrypto ? .coinbase : .frankfurter,
            observation: isCrypto
              ? (range == .day ? .hourlyClose : .dailyClose) : .dailyReference,
            timeZone: .gmt), fetchedAt: .now),
        issue: name == "cached" ? .usingCachedSeries : nil)
    }
  }

  var body: some Scene {
    WindowGroup {
      CurrencyDetailsEntry(
        flowID: flowID, input: .init(code: code, reference: "USD", snapshot: snapshot)
      )
      .environment(\.currencyDetailsDependencies, dependencies)
      .environment(appearance)
      .tint(appearance.accent)
      .preferredColorScheme(appearance.theme.colorScheme)
    }
  }
}
