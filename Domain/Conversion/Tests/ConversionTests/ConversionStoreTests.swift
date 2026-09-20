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

}
