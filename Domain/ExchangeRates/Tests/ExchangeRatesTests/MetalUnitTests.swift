import Foundation
import Testing

@testable import ExchangeRates

@Suite struct MetalUnitTests {
  private let snapshot = RateSnapshot(quotes: [
    "EUR": ExchangeRate(1, published: "2026-10-05", source: .init(provider: .custom("test"))),
    "USD": ExchangeRate(2, published: "2026-10-05", source: .init(provider: .custom("test"))),
    "XAU": ExchangeRate(
      Decimal(1) / 1000, published: "2026-10-05", source: .init(provider: .custom("test"))),
    "XAG": ExchangeRate(
      Decimal(1) / 10, published: "2026-10-05", source: .init(provider: .custom("test")))
  ])

  @Test func exactMassRepresentations() {
    #expect(MetalUnit.troyOunce.converted(1, to: .gram) == Decimal(311_034_768) / 10_000_000)
    #expect(MetalUnit.gram.converted(1000, to: .kilogram) == 1)
    #expect(MetalUnit.kilogram.converted(1, to: .gram) == 1000)
  }

  @Test(arguments: MetalUnit.allCases)
  func metalSourceAndDestinationUseTheSamePhysicalQuantity(_ unit: MetalUnit) throws {
    let oneOunce = MetalUnit.troyOunce.converted(1, to: unit)
    #expect(snapshot.convert(oneOunce, from: "XAU", to: "EUR", metalUnit: unit) == 1000)
    #expect(snapshot.convert(1000, from: "EUR", to: "XAU", metalUnit: unit) == oneOunce)
    #expect(snapshot.convert(3, from: "XAU", to: "XAG", metalUnit: unit) == 300)
    #expect(snapshot.convert(10, from: "EUR", to: "USD", metalUnit: unit) == 20)
    #expect(snapshot.convert(10, from: "XAU", to: "XAU", metalUnit: unit) == 10)
  }

  @Test func defaultPreservesProviderUnitAndFailureSemantics() {
    #expect(snapshot.convert(1, from: "XAU", to: "EUR") == 1000)
    #expect(snapshot.convert(1, from: "XAU", to: "JPY", metalUnit: .gram) == nil)
    #expect(snapshot.convert(.nan, from: "XAU", to: "XAU", metalUnit: .gram) == nil)
    #expect(snapshot.quotes["XAU"]?.value == Decimal(1) / 1000)
  }
}
