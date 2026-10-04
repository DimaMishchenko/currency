import Conversion
import CurrencyApplication
import ExchangeRates
import Foundation
import Testing

@Suite struct CurrencyEntityTests {
  @Test func searchableMetadataIncludesCodeNameAliasesAndArtwork() throws {
    for code in [CurrencyCode.usd, .eur, .btc, .xau] {
      let entity = CurrencyEntity(code.rawValue)
      let attributes = entity.attributeSet
      #expect(attributes.title?.contains(code.rawValue) == true)
      #expect(attributes.alternateNames?.contains(code.rawValue.lowercased()) == true)
      #expect(attributes.textContent?.contains(code.rawValue) == true)
      #expect(attributes.thumbnailData?.isEmpty == false)
    }
  }
  @MainActor @Test func converterDiscoveryHasRelevantKeywordsAndExistingHomeRoute() throws {
    let item = CurrencySearchIndex.converterItem
    #expect(item.attributeSet.keywords?.contains(String(localized: "exchange")) == true)
    #expect(item.attributeSet.keywords?.contains(String(localized: "convert")) == true)
    #expect(CurrencyRoute(url: try #require(item.attributeSet.contentURL)) == .converter)
  }
}
