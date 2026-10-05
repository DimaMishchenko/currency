import AppIntents

struct CurrencyShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ConvertAmountIntent(),
      phrases: [
        "Convert money with \(.applicationName)", "Convert \(\.$source) with \(.applicationName)"
      ], shortTitle: "Convert amount", systemImageName: "arrow.left.arrow.right")
    AppShortcut(
      intent: ConvertToMyCurrenciesIntent(),
      phrases: ["Convert to my currencies with \(.applicationName)"], shortTitle: "My currencies",
      systemImageName: "list.bullet")
    AppShortcut(
      intent: CheckRateIntent(),
      phrases: [
        "Check an exchange rate with \(.applicationName)",
        "Check the rate for \(\.$source) with \(.applicationName)"
      ], shortTitle: "Check a rate", systemImageName: "chart.line.uptrend.xyaxis")
  }
}
