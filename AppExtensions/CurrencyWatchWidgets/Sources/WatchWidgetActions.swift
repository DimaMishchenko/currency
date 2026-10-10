import AppIntents
import Conversion
import CurrencyApplication
import ExchangeRates
import Foundation
import WidgetKit
import Widgets

struct WatchWidgetPresetIntent: AppIntent {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "setAmount", defaultValue: "Set amount", table: "WatchWidgets")
  static var isDiscoverable: Bool { false }
  static var supportedModes: IntentModes { .background }
  @Parameter(
    title: LocalizedStringResource("input", defaultValue: "Widget input", table: "WatchWidgets"))
  var key: String
  @Parameter(
    title: LocalizedStringResource("currencies", defaultValue: "Currencies", table: "WatchWidgets"))
  var codes: [String]
  @Parameter(
    title: LocalizedStringResource("amount", defaultValue: "Amount", table: "WatchWidgets"))
  var amount: String
  @Parameter(
    title: LocalizedStringResource("amount", defaultValue: "Amount", table: "WatchWidgets"))
  var initialAmount: String
  @Parameter(
    title: LocalizedStringResource("kind", defaultValue: "Widget kind", table: "WatchWidgets"))
  var kind: String

  init() {}

  func perform() async throws -> some IntentResult {
    guard let amount = WidgetMath.parseAmount(amount) else {
      throw WatchWidgetActionError.invalidAmount
    }
    try WidgetStore(directory: WatchWidgetAppGroup.directory())
      .updateWidgetInput(
        key: key, codes: codes, amount: initialAmount
      ) { input in
        input.setMetalUnit(
          kind == WatchWidgetStyle.cash.kind ? .gram : WatchWidgetAppGroup.input().metalUnit)
        input.preset(amount)
      }
    WidgetCenter.shared.reloadTimelines(ofKind: kind)
    return .result()
  }
}

struct WatchWidgetSwapIntent: AppIntent {
  static let title: LocalizedStringResource = LocalizedStringResource(
    "swap", defaultValue: "Swap currencies", table: "WatchWidgets")
  static var isDiscoverable: Bool { false }
  static var supportedModes: IntentModes { .background }
  @Parameter(
    title: LocalizedStringResource("input", defaultValue: "Widget input", table: "WatchWidgets"))
  var key: String
  @Parameter(
    title: LocalizedStringResource("currencies", defaultValue: "Currencies", table: "WatchWidgets"))
  var codes: [String]
  @Parameter(
    title: LocalizedStringResource("amount", defaultValue: "Amount", table: "WatchWidgets"))
  var initialAmount: String
  @Parameter(
    title: LocalizedStringResource("kind", defaultValue: "Widget kind", table: "WatchWidgets"))
  var kind: String

  init() {}

  func perform() async throws -> some IntentResult {
    guard codes.count >= 2 else { return .result() }
    let directory = WatchWidgetAppGroup.directory()
    let rates = RateStore(directory: directory, policy: CurrencyRateConfiguration.policy)
      .loadRates()
    try WidgetStore(directory: directory)
      .updateWidgetInput(
        key: key, codes: codes, amount: initialAmount
      ) { input in
        input.setMetalUnit(WatchWidgetAppGroup.input().metalUnit)
        let target = input.active == codes[0] ? codes[1] : codes[0]
        if rates.convert(
          input.decimal, from: input.active, to: target, metalUnit: input.metalUnit) != nil
        {
          input.select(target, snapshot: rates)
        }
      }
    WidgetCenter.shared.reloadTimelines(ofKind: kind)
    return .result()
  }
}

enum WatchWidgetActionError: Error { case invalidAmount }

enum WatchWidgetAppGroup {
  static func input() -> ConverterState { ConversionStore(directory: directory()).input() }

  static func directory() -> URL {
    guard
      let directory = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.dimasike.currency.shared")
    else { preconditionFailure("Currency Watch widgets require the configured App Group.") }
    return directory
  }
}
