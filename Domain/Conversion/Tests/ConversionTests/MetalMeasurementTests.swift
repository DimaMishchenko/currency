import ExchangeRates
import Foundation
import Testing

@testable import Conversion

@Suite struct MetalMeasurementTests {
  private let snapshot = RateSnapshot(
    quotes: [
      "EUR": ExchangeRate(1, published: "2026-10-05", source: .init(provider: .custom("test"))),
      "XAU": ExchangeRate(
        Decimal(1) / 1000, published: "2026-10-05", source: .init(provider: .custom("test")))
    ], fetchedAt: .now)

  @Test func legacyRecordDefaultsToTroyOuncesAndKeepsAmount() throws {
    let input = try JSONDecoder()
      .decode(
        ConverterState.self, from: Data(#"{"amount":"12","from":"XAU","to":"USD"}"#.utf8))
    #expect(input.metalUnit == .troyOunce)
    #expect(input.amount == "12")
  }

  @Test func persistedPreferencePreservesSourceMassAcrossHosts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = ConversionStore(directory: directory)
    let widget = ConversionStore(directory: directory)
    try app.updateInput {
      $0.changeSource("XAU"); $0.setMetalUnit(.gram)
    }
    #expect(widget.input().metalUnit == .gram)
    #expect(widget.input().decimal == MetalUnit.troyOunce.gramsPerUnit)
    try app.updateInput { $0.setMetalUnit(.kilogram) }
    #expect(widget.input().decimal == MetalUnit.troyOunce.gramsPerUnit / 1000)
    try widget.updateInput { $0.setMetalUnit(.troyOunce) }
    #expect(app.input().decimal == 1)
  }

  @Test func preferenceDoesNotChangeFiatInputAndRepeatedSelectionIsInert() {
    var input = ConverterState()
    input.setAmount("123.45")
    input.setMetalUnit(.gram)
    #expect(input.amount == "123.45")
    let saved = input
    input.setMetalUnit(.gram)
    #expect(input == saved)
  }

  @Test func basePromotionAndEditorSelectionUseSelectedUnit() {
    var input = ConverterState()
    input.setAmount("1000")
    input.setDestinations(["XAU"])
    input.setMetalUnit(.gram)
    input.useAsBase("XAU", snapshot: snapshot)
    #expect(input.decimal == MetalUnit.troyOunce.gramsPerUnit)
    input.useAsBase("EUR", snapshot: snapshot)
    #expect(input.decimal == 1000)
    var editor = AmountEditor(codes: ["EUR", "XAU"], amount: "1000")
    editor.select("XAU", snapshot: snapshot, metalUnit: .gram)
    #expect(editor.decimal == MetalUnit.troyOunce.gramsPerUnit)
    editor.select("EUR", snapshot: snapshot, metalUnit: .gram)
    #expect(editor.decimal == 1000)
  }

  @Test func externalEvaluationRetainsUnitInValidatedRequest() throws {
    let request = try ConversionRequest(
      amount: "1000", source: "EUR", destinations: [.init(code: "XAU")], metalUnit: .gram)
    let result = try ConversionEvaluation(request: request, snapshot: snapshot, now: .now)
    #expect(result.request.metalUnit == .gram)
    #expect(result.results.first?.amount == "31.1034768")
  }

  @Test func kilogramPromotionKeepsSmallMetalAmountsNonzero() {
    var input = ConverterState()
    input.setAmount("1")
    input.setDestinations(["XAU"])
    input.setMetalUnit(.kilogram)
    input.useAsBase("XAU", snapshot: snapshot)
    #expect(input.decimal == Decimal(3_110_348) / 100_000_000_000)
    #expect(input.decimal > 0)
  }
}
