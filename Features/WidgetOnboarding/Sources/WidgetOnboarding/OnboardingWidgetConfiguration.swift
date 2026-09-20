import Conversion
import ExchangeRates
import Foundation
import Widgets

/// A pure projection of saved app choices. Missing rates never become made-up preview values.
public struct OnboardingWidgetConfiguration {
  /// The latest supplied rate or location observation.
  public let snapshot: RateSnapshot
  /// Temporary canonical input retained across preview size changes.
  public let input: ConverterState
  /// Ordered canonical currency codes used by this presentation.
  public let codes: [String]
  /// Whether missing compatible rates require an explicitly labeled demonstration.
  public let isSample: Bool

  /// Projects confirmed app choices into compatible preview currencies.
  public init(kind: WidgetShowcaseKind, snapshot: RateSnapshot, input: ConverterState) {
    let destinations = input.destinations.filter {
      guard let value = snapshot.convert(1, from: input.source, to: $0) else { return false }
      return value > 0 && !value.isNaN
    }
    let compatible = kind == .cash ? destinations.filter(WidgetPresets.allows) : destinations
    // Cash models banknotes and metal weights, so cryptocurrency pairs need an honest demo.
    isSample = kind == .cash && (!WidgetPresets.allows(input.source) || compatible.isEmpty)
    self.snapshot = isSample ? WidgetPreviewState.rates : snapshot
    var previewInput = input
    if isSample {
      previewInput = ConverterState()
      previewInput.changeSource(kind.codes[0])
      previewInput.setDestinations(Array(kind.codes.dropFirst()))
      previewInput.setAmount("100")
    } else {
      previewInput.setDestinations(compatible)
    }
    self.input = previewInput
    switch kind {
    case .calculator, .board:
      codes = [previewInput.source] + previewInput.destinations
    default:
      codes = [previewInput.source] + Array(previewInput.destinations.prefix(1))
    }
  }

}
