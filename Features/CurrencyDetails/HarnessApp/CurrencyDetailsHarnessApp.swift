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

  private var snapshot: RateSnapshot {
    RateSnapshot(
      quotes: [
        "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .ecb)),
        "USD": ExchangeRate(1.08, published: "2026-09-19", source: .init(provider: .ecb))
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
      let count = range == .week ? 7 : 30
      let points = (0..<count)
        .map {
          HistoryPoint(
            date: Date.now.addingTimeInterval(Double($0 - count) * 86_400),
            value: 1.08 + sin(Double($0) / 4) * 0.03)
        }
      return HistoryResult(
        series: HistorySeries(points: points, source: .init(provider: .ecb), fetchedAt: .now),
        issue: name == "cached" ? .usingCachedSeries : nil)
    }
  }

  var body: some Scene {
    WindowGroup {
      CurrencyDetailsEntry(
        flowID: flowID, input: .init(code: "EUR", reference: "USD", snapshot: snapshot)
      )
      .environment(\.currencyDetailsDependencies, dependencies)
      .environment(appearance)
      .tint(appearance.accent)
      .preferredColorScheme(appearance.theme.colorScheme)
    }
  }
}
