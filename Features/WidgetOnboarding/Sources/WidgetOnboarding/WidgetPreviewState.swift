import ExchangeRates
import Foundation
import Widgets

/// No store, persistence key, or network dependency. Sample rates are explicitly labeled by the host.
public struct WidgetPreviewState {
  /// Temporary canonical input retained across preview size changes.
  public var input: WidgetInput
  /// The latest supplied rate or location observation.
  public private(set) var snapshot: RateSnapshot
  /// Current rate information displayed by this flow.
  public static let rates = RateSnapshot(quotes: [
    "EUR": ExchangeRate(1, published: "", source: .init(provider: .custom("Preview"))),
    "USD": ExchangeRate(1.08, published: "", source: .init(provider: .custom("Preview"))),
    "GBP": ExchangeRate(0.84, published: "", source: .init(provider: .custom("Preview"))),
    "JPY": ExchangeRate(162, published: "", source: .init(provider: .custom("Preview"))),
    "CZK": ExchangeRate(25, published: "", source: .init(provider: .custom("Preview"))),
    "CHF": ExchangeRate(0.96, published: "", source: .init(provider: .custom("Preview"))),
    "CAD": ExchangeRate(1.48, published: "", source: .init(provider: .custom("Preview"))),
    "AUD": ExchangeRate(1.65, published: "", source: .init(provider: .custom("Preview"))),
    "SEK": ExchangeRate(11.4, published: "", source: .init(provider: .custom("Preview"))),
    "NOK": ExchangeRate(11.7, published: "", source: .init(provider: .custom("Preview"))),
    "PLN": ExchangeRate(4.3, published: "", source: .init(provider: .custom("Preview"))),
    "HUF": ExchangeRate(392, published: "", source: .init(provider: .custom("Preview")))
  ])
  /// Creates isolated demonstration input with supplied or explicitly labeled sample rates.
  public init(
    kind: WidgetShowcaseKind, snapshot: RateSnapshot = Self.rates,
    codes: [String]? = nil, amount: String? = nil
  ) {
    self.snapshot = snapshot
    input = WidgetInput(
      codes: codes ?? kind.codes, amount: amount ?? (kind == .cash ? "200" : "100"))
  }
  /// External coverage changes do not replay a user's temporary keypad or tile interaction.
  public mutating func update(snapshot: RateSnapshot, codes: [String]?, amount: String?) {
    self.snapshot = snapshot
    if let codes { input.reconcile(codes: codes) }
    if input.editedAt == nil, let amount, input.amount != amount {
      input = WidgetInput(codes: input.codes, amount: amount)
    }
  }

  /// Applies the same domain command reducer used by installed widget interactions.
  public mutating func apply(_ action: WidgetCommand) {
    action.apply(to: &input, snapshot: snapshot)
  }
}
