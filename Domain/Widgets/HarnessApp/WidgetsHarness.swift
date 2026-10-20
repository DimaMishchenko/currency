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
    "JPY": ExchangeRate(162, published: "", source: .init(provider: .custom("Harness"))),
    "CZK": ExchangeRate(25.1, published: "", source: .init(provider: .custom("Harness"))),
    "CHF": ExchangeRate(0.94, published: "", source: .init(provider: .custom("Harness"))),
    "CAD": ExchangeRate(1.47, published: "", source: .init(provider: .custom("Harness"))),
    "AUD": ExchangeRate(1.65, published: "", source: .init(provider: .custom("Harness"))),
    "CNY": ExchangeRate(7.82, published: "", source: .init(provider: .custom("Harness"))),
    "INR": ExchangeRate(90.4, published: "", source: .init(provider: .custom("Harness"))),
    "BTC": ExchangeRate(0.000016, published: "", source: .init(provider: .custom("Harness"))),
    "ETH": ExchangeRate(0.00042, published: "", source: .init(provider: .custom("Harness"))),
    "XAU": ExchangeRate(0.00046, published: "", source: .init(provider: .custom("Harness"))),
    "XAG": ExchangeRate(0.037, published: "", source: .init(provider: .custom("Harness"))),
    "SEK": ExchangeRate(11.4, published: "", source: .init(provider: .custom("Harness"))),
    "NOK": ExchangeRate(11.6, published: "", source: .init(provider: .custom("Harness"))),
    "DKK": ExchangeRate(7.46, published: "", source: .init(provider: .custom("Harness"))),
    "PLN": ExchangeRate(4.31, published: "", source: .init(provider: .custom("Harness"))),
    "HUF": ExchangeRate(394, published: "", source: .init(provider: .custom("Harness"))),
    "RON": ExchangeRate(4.97, published: "", source: .init(provider: .custom("Harness"))),
    "BRL": ExchangeRate(5.62, published: "", source: .init(provider: .custom("Harness"))),
    "MXN": ExchangeRate(19.8, published: "", source: .init(provider: .custom("Harness"))),
    "NZD": ExchangeRate(1.79, published: "", source: .init(provider: .custom("Harness"))),
    "SGD": ExchangeRate(1.46, published: "", source: .init(provider: .custom("Harness"))),
    "HKD": ExchangeRate(8.43, published: "", source: .init(provider: .custom("Harness"))),
    "ZAR": ExchangeRate(20.1, published: "", source: .init(provider: .custom("Harness")))
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
    if scenario.hasPrefix("calculator-") {
      CalculatorWidgetHarness(scenario: scenario)
    } else if scenario == "history-crypto-freshness" {
      CryptoHistoryWidgetHarness()
    } else if scenario.hasPrefix("history") {
      HistoryWidgetHarness(scenario: scenario)
    } else if scenario.hasPrefix("board") {
      boardWidgets
    } else {
      standardWidgets
    }
  }

  private var boardEntry: SuiteEntry {
    let date = Date(timeIntervalSince1970: 1_790_035_200)
    let allCodes = [
      "EUR", "USD", "GBP", "JPY", "CZK", "CHF", "CAD", "AUD", "CNY", "INR", "BTC", "ETH",
      "XAU", "XAG", "SEK", "NOK", "DKK", "PLN", "HUF", "RON", "BRL", "MXN", "NZD", "SGD",
      "HKD", "ZAR"
    ]
    let codes: [String]
    switch scenario {
    case "board-many", "board-long", "board-dark":
      codes = allCodes
    case "board-local", "board-stale":
      codes = allCodes.filter { $0 != "CZK" } + [WidgetSelection.localID]
    case "board-custom":
      codes = ["EUR"]
    default:
      codes = ["EUR", "USD", "GBP", "JPY"]
    }
    let amount = scenario == "board-long" ? "123456789.12345678" : "100"
    var spec = WidgetSpec(
      kind: "harness", codes: codes, amount: amount,
      location: scenario == "board-stale"
        ? WidgetLocation(country: "CZ", currency: "CZK", updatedAt: .distantPast) : nil,
      status: scenario == "board-stale" ? .failed : .notDetermined)
    spec.requiresCurrencySelection = scenario == "board-custom"
    return SuiteEntry(
      date: date, spec: spec, input: WidgetInput(codes: spec.codes, amount: amount),
      snapshot: snapshot)
  }

  private var boardWidgets: some View {
    ScrollView {
      VStack(spacing: 20) {
        Text("Board · " + scenario).font(.headline)
        let compact = ProcessInfo.processInfo.arguments.contains("--compact")
        if !ProcessInfo.processInfo.arguments.contains("--large") {
          boardPreview(.systemSmall, name: "Small", width: 170, height: compact ? 164 : 170)
          boardPreview(.systemMedium, name: "Medium", width: 364, height: compact ? 164 : 170)
        }
        let largeHeight: CGFloat =
          compact ? 364 : 382
        boardPreview(.systemLarge, name: "Large", width: 364, height: largeHeight)
      }
      .padding(.vertical, 16)
      .frame(maxWidth: .infinity)
    }
    .background(Color(uiColor: .secondarySystemBackground))
    .environment(\.isWidgetPreview, true)
    .environment(\.locale, Locale(identifier: "en_US"))
    .preferredColorScheme(scenario == "board-dark" ? .dark : .light)
  }

  private func boardPreview(
    _ family: WidgetFamily, name: String, width: CGFloat, height: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(name).font(.caption).foregroundStyle(.secondary)
      BoardLayout(family: family, entry: boardEntry)
        .padding(16)
        .frame(width: width, height: height)
        .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 24))
        .clipShape(.rect(cornerRadius: 24))
    }
  }

  private var standardWidgets: some View {
    ScrollView {
      VStack(spacing: 24) {
        Text("Production widgets").font(.title)
        if scenario == "cash" {
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
