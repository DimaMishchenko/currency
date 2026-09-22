import Conversion
import ExchangeRates
import LocalCurrency
import SwiftUI
import WidgetKit
import Widgets
import WidgetsUI

@main
struct WidgetsHarness: App {
  var body: some Scene { WindowGroup { WidgetHarnessContent() } }
}

private struct WidgetHarnessContent: View {
  private let scenario = ProcessInfo.processInfo.arguments.dropFirst().first ?? "calculator"
  @State private var input = WidgetInput(codes: ["EUR", "USD", "GBP", "JPY"], amount: "100")
  private let snapshot = RateSnapshot(quotes: [
    "EUR": ExchangeRate(1, published: "", source: .init(provider: .custom("Harness"))),
    "USD": ExchangeRate(1.08, published: "", source: .init(provider: .custom("Harness"))),
    "GBP": ExchangeRate(0.84, published: "", source: .init(provider: .custom("Harness"))),
    "JPY": ExchangeRate(162, published: "", source: .init(provider: .custom("Harness")))
  ])
  private var entry: SuiteEntry {
    let codes = scenario == "location" ? ["EUR", WidgetSelection.localID] : input.codes
    return SuiteEntry(
      date: .now,
      spec: WidgetSpec(kind: "harness", codes: codes, amount: input.amount, status: .notDetermined),
      input: scenario == "location" ? WidgetInput(codes: codes, amount: input.amount) : input,
      snapshot: scenario == "unavailable" ? RateSnapshot() : snapshot)
  }
  @ViewBuilder var body: some View {
    if scenario.hasPrefix("history") {
      HistoryWidgetHarness(scenario: scenario)
    } else {
      standardWidgets
    }
  }

  private var standardWidgets: some View {
    ScrollView {
      VStack(spacing: 24) {
        Text("Production widgets").font(.title)
        if scenario == "board" {
          BoardLayout(family: .systemLarge, entry: entry).frame(height: 364)
        } else if scenario == "cash" {
          CashView(entry: entry).frame(height: 164)
        } else if scenario == "icon" {
          CurrencySymbolLayout(symbol: .euro).frame(width: 76, height: 76)
        } else {
          CalculatorLayout(entry: entry, family: .systemMedium).frame(height: 164)
          CalculatorLayout(entry: entry, family: .systemLarge).frame(height: 364)
        }
      }
      .padding(16).frame(maxWidth: 380)
    }
    .environment(\.isWidgetPreview, true)
    .environment(
      \.widgetButtonRenderer,
      WidgetButtonRenderer { command, label in
        AnyView(
          Button {
            command.apply(to: &input, snapshot: snapshot)
          } label: {
            label
          })
      })
  }
}
