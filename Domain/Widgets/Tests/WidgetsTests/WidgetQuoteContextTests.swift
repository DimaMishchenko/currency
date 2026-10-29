import ExchangeRates
import Foundation
import Testing

@testable import Widgets

@Suite struct WidgetQuoteContextTests {
  @Test func retainsRenderedQuoteAfterTheSharedCacheAdvancesAndExpires() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetQuoteContextStore(directory: directory)
    let now = Date.now
    let old = RateSnapshot(
      quotes: [
        "USD": ExchangeRate(
          1.1, published: "2026-10-16",
          source: .init(provider: .frankfurter))
      ], fetchedAt: now)
    let rates = RateStore(directory: directory)
    _ = try rates.saveBootstrapRates(old, now: now)
    let url = try #require(try store.save(old, now: now))
    let newer = RateSnapshot(
      quotes: [
        "USD": ExchangeRate(
          1.2, published: "2026-10-16",
          source: .init(provider: .frankfurter))
      ], fetchedAt: now.addingTimeInterval(60))
    _ = try rates.saveBootstrapRates(newer, now: now.addingTimeInterval(60))
    #expect(rates.loadRates().quotes["USD"]?.value == 1.2)
    let value = try #require(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "context" }?
        .value)
    let id = try #require(UUID(uuidString: value))
    #expect(try store.save(old, now: now.addingTimeInterval(60)) == url)
    #expect(store.load(id, now: now.addingTimeInterval(60))?.quotes["USD"]?.value == 1.1)
    #expect(store.load(id, now: now.addingTimeInterval(WidgetQuoteContextStore.lifetime)) == nil)
    #expect(store.load(UUID(), now: now) == nil)
    let pairURL = try #require(try store.save(old, base: "BTC", quote: "USD", now: now))
    #expect(pairURL != url)
    let pairValue = try #require(
      URLComponents(url: pairURL, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == "context" }?
        .value)
    let pairID = try #require(UUID(uuidString: pairValue))
    #expect(store.context(pairID, now: now)?.base == "BTC")
    #expect(store.context(pairID, now: now)?.quote == "USD")
  }

  @Test func historyDestinationsRetainDistinctPeriodsAndMeasurements() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetQuoteContextStore(directory: directory)
    let now = Date.now
    let snapshot = fullSnapshot(now: now)
    let ordinary = try #require(try store.save(snapshot, base: "BTC", quote: "USD", now: now))
    let day = try #require(
      try store.save(
        snapshot, base: "BTC", quote: "USD", historyRange: .day, metalUnit: .gram, now: now))
    let week = try #require(
      try store.save(
        snapshot, base: "BTC", quote: "USD", historyRange: .week, metalUnit: .gram, now: now))
    #expect(ordinary != day)
    #expect(day != week)
    let id = try contextID(week)
    let context = try #require(store.context(id, now: now))
    #expect(context.historyRange == .week)
    #expect(context.metalUnit == .gram)
    #expect(store.context(try contextID(ordinary), now: now)?.historyRange == nil)
    #expect(store.context(id, now: now.addingTimeInterval(WidgetQuoteContextStore.lifetime)) == nil)
  }

  @Test func timelineSaveBypassesUnreadableLegacyAggregate() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let legacyURL = directory.appendingPathComponent("widget-quote-contexts.json")
    let legacy = Data(repeating: 0x78, count: 16_777_216)
    try legacy.write(to: legacyURL)
    let store = WidgetQuoteContextStore(directory: directory)
    let now = Date.now
    let snapshot = fullSnapshot(now: now)
    let url = try #require(try store.save(snapshot, now: now))
    let id = try contextID(url)
    #expect(store.context(id, now: now)?.snapshot.quotes.count == CurrencyCatalog.codes.count)
    #expect(try Data(contentsOf: legacyURL) == legacy)
    let index = directory.appendingPathComponent("widget-quote-contexts-v2/index.json")
    #expect(try Data(contentsOf: index).count < 1024)
  }

  @Test func existingLegacyURLsSurviveNewTimelineSaves() throws {
    struct LegacyRecord: Encodable {
      let id: UUID
      let digest: String
      let createdAt: Date
      let snapshot: RateSnapshot
      let base: String
      let quote: String
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = Date.now
    let id = UUID()
    let snapshot = fullSnapshot(now: now)
    let data = try JSONEncoder()
      .encode([
        LegacyRecord(
          id: id, digest: "legacy", createdAt: now, snapshot: snapshot, base: "BTC", quote: "USD")
      ])
    let legacyURL = directory.appendingPathComponent("widget-quote-contexts.json")
    try data.write(to: legacyURL)
    let store = WidgetQuoteContextStore(directory: directory)
    _ = try store.save(snapshot, now: now)
    #expect(store.context(id, now: now)?.base == "BTC")
    #expect(store.context(id, now: now)?.quote == "USD")
    #expect(store.context(id, now: now)?.snapshot.quotes["USD"]?.value == 1.125)
    #expect(store.context(id, now: now.addingTimeInterval(WidgetQuoteContextStore.lifetime)) == nil)
    #expect(try Data(contentsOf: legacyURL) == data)
  }

  @Test func contextCapacityBoundsIndividualFilesAndPreservesNewest() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetQuoteContextStore(directory: directory)
    let now = Date.now
    var ids: [UUID] = []
    for offset in 0...WidgetQuoteContextStore.capacity {
      let time = now.addingTimeInterval(Double(offset))
      let snapshot = RateSnapshot(
        quotes: [
          "USD": ExchangeRate(
            Decimal(offset + 1), published: "2026-10-20",
            source: .init(provider: .fawaz))
        ], fetchedAt: time)
      ids.append(try contextID(#require(try store.save(snapshot, now: time))))
    }
    let time = now.addingTimeInterval(Double(WidgetQuoteContextStore.capacity))
    #expect(store.context(ids[0], now: time) == nil)
    #expect(store.context(try #require(ids.last), now: time)?.snapshot.quotes["USD"]?.value == 129)
    let files = try FileManager.default.contentsOfDirectory(
      at: directory.appendingPathComponent("widget-quote-contexts-v2"),
      includingPropertiesForKeys: nil)
    #expect(files.count == WidgetQuoteContextStore.capacity + 1)
    #expect(
      try Data(
        contentsOf: directory.appendingPathComponent(
          "widget-quote-contexts-v2/index.json")
      )
      .count < 65_536)
  }

  @Test func saveRecoversOrphanedContextFilesWithoutReadingOrRemovingUnrelatedFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date.now
    let store = WidgetQuoteContextStore(directory: directory)
    let snapshot = fullSnapshot(now: now)
    let url = try #require(try store.save(snapshot, now: now))
    let id = try contextID(url)
    let records = directory.appendingPathComponent("widget-quote-contexts-v2")
    let orphan = records.appendingPathComponent(UUID().uuidString + ".json")
    let expiredOrphan = records.appendingPathComponent(UUID().uuidString + ".json")
    let unrelatedJSON = records.appendingPathComponent("unrelated.json")
    let unrelatedText = records.appendingPathComponent(UUID().uuidString + ".txt")
    let unreadableRecord = Data("incomplete record".utf8)
    for file in [orphan, expiredOrphan, unrelatedJSON, unrelatedText] {
      try unreadableRecord.write(to: file)
    }
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-WidgetQuoteContextStore.lifetime - 1)],
      ofItemAtPath: expiredOrphan.path)

    #expect(try store.save(snapshot, now: now.addingTimeInterval(1)) == url)
    #expect(!FileManager.default.fileExists(atPath: orphan.path))
    #expect(!FileManager.default.fileExists(atPath: expiredOrphan.path))
    #expect(try Data(contentsOf: unrelatedJSON) == unreadableRecord)
    #expect(try Data(contentsOf: unrelatedText) == unreadableRecord)
    #expect(store.context(id, now: now)?.snapshot.quotes.count == CurrencyCatalog.codes.count)
    let remaining = try FileManager.default.contentsOfDirectory(
      at: records, includingPropertiesForKeys: nil)
    #expect(
      Set(remaining.map(\.lastPathComponent)) == [
        "index.json", id.uuidString + ".json", "unrelated.json", unrelatedText.lastPathComponent
      ])
  }

  private func contextID(_ url: URL) throws -> UUID {
    let value = try #require(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "context" }?
        .value)
    return try #require(UUID(uuidString: value))
  }

  private func fullSnapshot(now: Date) -> RateSnapshot {
    let quotes = Dictionary(
      uniqueKeysWithValues: CurrencyCatalog.codes.map { code in
        (
          code,
          ExchangeRate(
            1.125, published: "2026-10-20",
            source: .init(provider: .fawaz, observation: .dailyRate), cachedAt: now)
        )
      })
    return RateSnapshot(
      quotes: quotes, fetchedAt: now, dailyQuotes: quotes, dailyFetchedAt: now,
      checkedAt: now, supplementalFetchedAt: now, fiatQuotes: [:], supplementalQuotes: quotes)
  }

}
