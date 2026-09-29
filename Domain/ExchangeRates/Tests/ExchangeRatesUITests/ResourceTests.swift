import ExchangeRates
import ExchangeRatesUI
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@Suite struct ResourceTests {
  @Test func provenanceInterpolationUsesTheOwningCatalog() {
    #expect(
      RateMessages.providerDescription(
        RateSource(provider: .coinbase, observation: .dailyClose, timeZone: .gmt),
        locale: Locale(identifier: "en_US")) == "Coinbase · daily closes · GMT")
    #expect(
      RateMessages.providerDescription(
        RateSource(provider: .custom("Example"), observation: .exchangeRate),
        locale: Locale(identifier: "en_US")) == "Example · retrieved")
  }
  @Test(arguments: CurrencyCatalog.codes)
  func systemPickerArtworkIsValidAndFitsItsPixelBudget(_ code: String) throws {
    let data = try #require(CurrencyIcon.pickerImageData(code))
    let image = try pngImage(data)
    #expect(image.width > 0 && image.width <= 72)
    #expect(image.height > 0 && image.height <= 72)
  }

  @Test func searchThumbnailKeepsItsResolutionSeparateFromPickerArtwork() throws {
    let picker = try #require(CurrencyIcon.pickerImageData("EUR"))
    let thumbnail = try #require(CurrencyIcon.thumbnailImageData("EUR"))
    let small = try pngImage(picker)
    let large = try pngImage(thumbnail)
    #expect(small.width == 72 && small.height == 72)
    #expect(large.width == 216 && large.height == 216)
    #expect(CurrencyIcon.pickerImageData("EUR") == picker)
    #expect(CurrencyIcon.thumbnailImageData("EUR") == thumbnail)
  }

  @Test(arguments: ["", "invalid", "eur", "@local"])
  func unknownCurrencyArtworkIsAbsent(_ code: String) {
    #expect(CurrencyIcon.pickerImageData(code) == nil)
    #expect(CurrencyIcon.thumbnailImageData(code) == nil)
  }

  @Test func concurrentArtworkRequestsKeepRepeatResultsConsistent() async throws {
    let codes = ["EUR", "USD", "BTC", "XAU"]
    var expected: [String: Data] = [:]
    for code in codes {
      expected[code] = try #require(CurrencyIcon.pickerImageData(code))
    }
    await withTaskGroup(of: (String, Data?).self) { group in
      for pass in 0..<32 {
        let code = codes[pass % codes.count]
        group.addTask { (code, CurrencyIcon.pickerImageData(code)) }
      }
      for await (code, data) in group { #expect(data == expected[code]) }
    }
  }

  private func pngImage(_ data: Data) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    #expect(CGImageSourceGetCount(source) == 1)
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }
}
