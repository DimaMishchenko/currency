import ExchangeRates
import Foundation
import Testing
import Widgets

@Suite struct HistoryWidgetRefreshTests {
  @Test func sharedEndpointReloadsOnceAcrossStoreInstancesAndRanges() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let point = HistoryPoint(date: .now, value: 52_500)
    let first = WidgetStore(directory: directory)
    #expect(try first.claimHistoryQuoteRefresh(base: "BTC", quote: "USD", point: point))
    let sibling = WidgetStore(directory: directory)
    #expect(try !sibling.claimHistoryQuoteRefresh(base: "BTC", quote: "USD", point: point))
    let advanced = HistoryPoint(date: point.date.addingTimeInterval(60), value: 53_000)
    #expect(try sibling.claimHistoryQuoteRefresh(base: "BTC", quote: "USD", point: advanced))
    #expect(try !first.claimHistoryQuoteRefresh(base: "BTC", quote: "USD", point: advanced))
    #expect(try !first.claimHistoryQuoteRefresh(base: "BTC", quote: "USD", point: point))
    #expect(try first.claimHistoryQuoteRefresh(base: "BTC", quote: "EUR", point: advanced))
  }

  @Test func correctedPriceAndUnchangedPriceWithNewObservationEachReloadOnce() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    let now = Date.now
    for point in [
      HistoryPoint(date: now, value: 52_500),
      HistoryPoint(date: now, value: 53_000),
      HistoryPoint(date: now.addingTimeInterval(60), value: 53_000)
    ] {
      #expect(try store.claimHistoryQuoteRefresh(base: "BTC", quote: "USD", point: point))
      #expect(try !store.claimHistoryQuoteRefresh(base: "BTC", quote: "USD", point: point))
    }
  }

  @Test func simultaneousSiblingClaimsScheduleOneReload() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let point = HistoryPoint(date: .now, value: 52_500)
    let claims = try await withThrowingTaskGroup(of: Bool.self) { group in
      for _ in 0..<16 {
        group.addTask {
          try WidgetStore(directory: directory)
            .claimHistoryQuoteRefresh(base: "BTC", quote: "USD", point: point)
        }
      }
      var count = 0
      for try await claimed in group where claimed { count += 1 }
      return count
    }
    #expect(claims == 1)
  }

  @Test func corruptRecordDoesNotCauseRepeatedReloadsOrOverwriteEvidence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    let point = HistoryPoint(date: .now, value: 52_500)
    #expect(try store.claimHistoryQuoteRefresh(base: "BTC", quote: "USD", point: point))
    let url = try #require(
      FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    let invalid = Data("invalid".utf8)
    try invalid.write(to: url)
    #expect(throws: (any Error).self) {
      try store.claimHistoryQuoteRefresh(base: "BTC", quote: "USD", point: point)
    }
    #expect(try Data(contentsOf: url) == invalid)
  }
}
