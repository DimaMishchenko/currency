import Foundation
import RateCore

// One file per concern: widget key presses cannot overwrite network updates.
enum SharedStore {
    static let group = "group.com.dima.currency"
    static var directory: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Currency")
    }
    static var rates: DiskStore { DiskStore(directory: directory) }
    static func input() -> InputState {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("input.json")), let input = try? JSONDecoder().decode(InputState.self, from: data) else { return InputState() }
        return input
    }
    static func save(_ input: InputState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(input).write(to: directory.appendingPathComponent("input.json"), options: .atomic)
    }
}
