import Conversion
import Foundation
import Testing

@Suite struct ConversionUsageStoreTests {
  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  @Test func thresholdSurvivesNewInstancesAndResetsAfterClaim() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConversionUsageStore(directory: directory)
    #expect(try !store.claimReviewRequest())
    for _ in 0..<2 { try store.recordConversion() }
    #expect(try !ConversionUsageStore(directory: directory).claimReviewRequest())
    try ConversionUsageStore(directory: directory).recordConversion()
    #expect(try store.claimReviewRequest())
    #expect(try !store.claimReviewRequest())
    for _ in 0..<3 { try store.recordConversion() }
    #expect(try ConversionUsageStore(directory: directory).claimReviewRequest())
  }

  @Test func widgetSessionsUseLastActivityAndIndependentKeys() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConversionUsageStore(directory: directory)
    let start = Date(timeIntervalSince1970: 10_000)
    for seconds: TimeInterval in [0, 29, 58, 87] {
      try ConversionUsageStore(directory: directory)
        .recordWidgetConversion(
          key: "default", now: start.addingTimeInterval(seconds))
    }
    try store.recordWidgetConversion(key: "custom", now: start)
    #expect(try !store.claimReviewRequest())
    try store.recordWidgetConversion(key: "default", now: start.addingTimeInterval(117))
    #expect(try store.claimReviewRequest())
    try store.recordWidgetConversion(key: "default", now: start.addingTimeInterval(118))
    #expect(try !store.claimReviewRequest())
  }

  @Test(arguments: [
    Data("invalid".utf8), Data("{}".utf8),
    Data(#"{"version":2,"count":3,"widgetActivity":{}}"#.utf8),
    Data(#"{"version":1,"count":-1,"widgetActivity":{}}"#.utf8)
  ])
  func incompatibleRecordIsPreserved(_ original: Data) throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("conversion-usage.json")
    try original.write(to: url)
    let store = ConversionUsageStore(directory: directory)
    #expect(throws: (any Error).self) { try store.recordConversion() }
    #expect(throws: (any Error).self) {
      try store.recordWidgetConversion(key: "default", now: .now)
    }
    #expect(throws: (any Error).self) { try store.claimReviewRequest() }
    #expect(try Data(contentsOf: url) == original)
  }

  @Test func unreadableRecordIsPreserved() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("conversion-usage.json")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    #expect(throws: (any Error).self) {
      try ConversionUsageStore(directory: directory).recordConversion()
    }
    #expect(try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
  }

  @Test func concurrentClaimsHaveOneWinner() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for _ in 0..<3 { try ConversionUsageStore(directory: directory).recordConversion() }
    let winners = try await withThrowingTaskGroup(of: Bool.self) { group in
      for _ in 0..<20 {
        group.addTask { try ConversionUsageStore(directory: directory).claimReviewRequest() }
      }
      var wins = 0
      for try await claimed in group where claimed { wins += 1 }
      return wins
    }
    #expect(winners == 1)
  }
}
