import CurrencySupport
import ExchangeRates
import WidgetKit

/// A snapshot rendered identically by the extension and the in-app preview.
public struct SuiteEntry: TimelineEntry {
  /// Timeline activation date.
  public var date: Date
  /// Full widget configuration.
  public var spec: WidgetSpec
  /// Editable widget value and active currency.
  public var input: WidgetInput
  /// Cached or explicitly labeled sample rates.
  public var snapshot: RateSnapshot
  /// Creates a presentation snapshot without fetching or saving data.
  public init(date: Date, spec: WidgetSpec, input: WidgetInput, snapshot: RateSnapshot) {
    self.date = date; self.spec = spec; self.input = input; self.snapshot = snapshot
  }
}
