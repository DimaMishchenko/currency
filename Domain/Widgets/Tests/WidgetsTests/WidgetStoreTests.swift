import Foundation
import Testing
import Widgets

struct WidgetStoreTests {
  @Test func absentRecordStartsConfiguredInput() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = try WidgetStore(directory: directory)
      .updateWidgetInput(
        key: "new", codes: ["EUR", "USD"], amount: "42", mutation: { _ in })
    #expect(input.amount == "42")
  }

  @Test(arguments: [Data("invalid".utf8), Data("{\"amount\":[]}".utf8)])
  func incompatibleRecordIsPreservedAndMutationNeverRuns(_ original: Data) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    try store.updateWidgetInput(key: "existing", codes: ["EUR", "USD"], mutation: { _ in })
    let url = try #require(
      FileManager.default
        .contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: nil
        )
        .first)
    try original.write(to: url)
    var invoked = false
    #expect(throws: (any Error).self) {
      try store.updateWidgetInput(key: "existing", codes: ["EUR", "USD"]) { _ in invoked = true }
    }
    #expect(!invoked)
    #expect(try Data(contentsOf: url) == original)
    #expect(store.widgetInput(key: "existing", codes: ["EUR", "USD"]).amount == "1")
  }

  @Test func unreadableRecordDoesNotBecomeFreshInput() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetStore(directory: directory)
    try store.updateWidgetInput(key: "existing", codes: ["EUR"], mutation: { _ in })
    let url = try #require(
      FileManager.default
        .contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: nil
        )
        .first)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var invoked = false
    #expect(throws: (any Error).self) {
      try store.updateWidgetInput(key: "existing", codes: ["EUR"]) { _ in invoked = true }
    }
    #expect(!invoked)
    #expect(
      try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory
        == true)
  }
}
