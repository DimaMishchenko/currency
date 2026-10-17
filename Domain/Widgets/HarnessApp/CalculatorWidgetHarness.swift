import Conversion
import ExchangeRates
import SwiftUI
import WidgetKit
import Widgets
import WidgetsUI

struct CalculatorWidgetHarness: View {
  let scenario: String
  @State private var input: WidgetInput

  private static let snapshot = RateSnapshot(quotes: [
    "AED": quote("3.6725"), "EUR": quote("0.89"), "GBP": quote("0.755"),
    "BTC": quote("0.0000121188"), "ETH": quote("0.000403"), "CHF": quote("0.828"),
    "USD": quote("1"), "XAU": quote("0.000241")
  ])

  private static func quote(_ text: String) -> ExchangeRate {
    guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
      preconditionFailure("Invalid calculator fixture rate")
    }
    return ExchangeRate(value, published: "", source: .init(provider: .custom("Harness")))
  }

  init(scenario: String) {
    self.scenario = scenario
    let count = Int(scenario.split(separator: "-").dropFirst().first ?? "8") ?? 8
    var codes =
      count == 2
      ? ["AED", "BTC"]
      : Array(["AED", "EUR", "GBP", "BTC", "ETH", "CHF", "USD", "XAU"].prefix(count))
    if scenario.contains("metals"), !codes.isEmpty { codes[codes.count - 1] = "XAU" }
    var input = WidgetInput(
      codes: codes, amount: count == 8 ? "47" : count == 6 ? "124" : "12447",
      metalUnit: scenario.contains("grams") ? .gram : .troyOunce)
    if count == 8 { input.select("USD", snapshot: Self.snapshot) }
    if scenario.contains("long") {
      input.press("AC")
      for key in "123456789.1234" { input.press(String(key)) }
    }
    _input = State(initialValue: input)
  }

  private var entry: SuiteEntry {
    SuiteEntry(
      date: .now,
      spec: WidgetSpec(
        kind: "harness", codes: input.codes, amount: input.amount, status: .notDetermined),
      input: input, snapshot: Self.snapshot)
  }

  var body: some View {
    let medium = scenario.contains("medium")
    VStack(spacing: 16) {
      CalculatorLayout(entry: entry, family: medium ? .systemMedium : .systemLarge)
        .frame(height: medium ? 138 : 328)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 30))
        .frame(maxWidth: 370)
      Text("Currency").font(.caption.weight(.medium))
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.top, 24)
    .background(Color(uiColor: .systemGroupedBackground))
    .environment(\.isWidgetPreview, true)
    .environment(
      \.widgetButtonRenderer,
      WidgetButtonRenderer { command, label in
        AnyView(
          Button {
            command.apply(to: &input, snapshot: Self.snapshot)
          } label: {
            label
          })
      })
  }
}
