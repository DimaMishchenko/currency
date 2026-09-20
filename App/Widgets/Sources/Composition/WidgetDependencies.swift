import Conversion
import ExchangeRates
import Foundation
import LocalCurrency
import Widgets

/// Capabilities supplied to WidgetKit timeline providers by extension composition.
struct WidgetTimelineDependencies: Sendable {
  let input: @Sendable () -> ConverterState
  let rates: @Sendable () -> RateSnapshot
  let location: @Sendable () -> WidgetLocation?
  let locationStatus: @Sendable () -> WidgetLocationStatus
  let widgetInput: @Sendable (_ key: String, _ codes: [String], _ amount: String) -> WidgetInput
  let refreshRates: @Sendable (_ force: Bool) async throws -> RefreshResult
  let refreshLocalCurrency: @Sendable () async -> Void
  let now: @Sendable () -> Date
}

/// Focused capabilities for one installed AppIntent interaction.
struct WidgetActionDependencies: Sendable {
  let rates: @Sendable () -> RateSnapshot
  let apply: @Sendable (WidgetCommand, String, RateSnapshot?) throws -> Bool
  let reloadSynchronizedWidgets: @Sendable () -> Void
}
