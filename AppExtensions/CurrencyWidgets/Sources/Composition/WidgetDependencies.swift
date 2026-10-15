import Conversion
import ExchangeRates
import Foundation
import LocalCurrency
import Widgets

struct WidgetTimelineDependencies: Sendable {
  let input: @Sendable () -> ConverterState
  let rates: @Sendable () -> RateSnapshot
  let localSnapshot: @Sendable () -> (WidgetLocation?, WidgetLocationStatus)
  let widgetInput: @Sendable (_ key: String, _ codes: [String], _ amount: String) -> WidgetInput
  let refreshRates: @Sendable (_ force: Bool) async throws -> RefreshResult
  let refreshLocalCurrency: @Sendable () async -> Void
  let now: @Sendable () -> Date
  var refreshInterval: TimeInterval = 1_800
}

struct WidgetActionDependencies: Sendable {
  let rates: @Sendable () -> RateSnapshot
  let apply: @Sendable (WidgetCommand, String, RateSnapshot?) throws -> Bool
  let reloadSynchronizedWidgets: @Sendable () -> Void
}
