import Conversion
import Foundation
import Testing

@Suite struct ConversionStoreTests {
  @Test func interleavedHostsPreserveAmountAndSelectionEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = ConversionStore(directory: directory)
    let widget = ConversionStore(directory: directory)
    let displayed = app.input()
    try widget.press("AC")
    try widget.press("4")
    try widget.press("2")
    let updated = try app.updateInput { $0.setDestinations($0.destinations + ["PLN"]) }
    #expect(displayed.amount == "1")
    #expect(updated.amount == "42")
    #expect(widget.input().destinations.contains("PLN"))
    try app.updateInput { $0.moveDestinations(["GBP"], before: "USD") }
    #expect(widget.input().destinations.first == "GBP")
    #expect(widget.input().destinations.contains("PLN"))
  }

  @Test(arguments: [Data("invalid".utf8), Data("{\"source\":[]}".utf8)])
  func incompatibleRecordIsPreservedAndMutationNeverRuns(_ original: Data) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("input.json")
    try original.write(to: url)
    let store = ConversionStore(directory: directory)
    var invoked = false
    #expect(throws: (any Error).self) {
      try store.updateInput { _ in invoked = true }
    }
    #expect(!invoked)
    #expect(try Data(contentsOf: url) == original)
    #expect(store.input() == ConverterState())
  }

  @Test func unreadableRecordDoesNotBecomeFreshInput() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("input.json")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var invoked = false
    #expect(throws: (any Error).self) {
      try ConversionStore(directory: directory).updateInput { _ in invoked = true }
    }
    #expect(!invoked)
    #expect(try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
  }

}
