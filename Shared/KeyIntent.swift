import Foundation
import AppIntents
import WidgetKit
import RateCore

struct KeyIntent: AppIntent {
    static let title: LocalizedStringResource = "Enter amount"
    @Parameter(title: "Key") var key: String
    init() {}
    init(_ key: String) { self.key = key }
    func perform() async throws -> some IntentResult {
        // Coordinate the read/modify/write across widget extension processes.
        let url = SharedStore.directory.appendingPathComponent("input.json")
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { _ in
            var state = SharedStore.input(); state.press(key)
            do { try SharedStore.save(state) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError as NSError? { throw error }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
