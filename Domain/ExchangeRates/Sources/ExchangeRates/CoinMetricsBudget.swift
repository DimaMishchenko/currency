import CoordinatedFiles
import Foundation

struct CoinMetricsBudget: Sendable {
  let directory: URL?

  struct State: Codable {
    var nextStart: Date = .distantPast
    var cooldown: Date = .distantPast
    var lease: Lease?
  }

  struct Lease: Codable {
    let owner: UUID
    let expires: Date
  }

  func acquire() async throws -> UUID {
    let owner = UUID()
    while true {
      try Task.checkCancellation()
      let wait: TimeInterval
      if let directory {
        wait = try Self.update(directory: directory) { Self.reserve(&$0, owner: owner) }
      } else {
        wait = await ProcessBudget.shared.reserve(owner: owner)
      }
      if wait == 0 { return owner }
      try await Task.sleep(for: .seconds(min(wait, 1)))
    }
  }

  func finish(_ owner: UUID, cooldown: Date? = nil) async throws {
    if let directory {
      try Self.update(directory: directory) { Self.release(&$0, owner: owner, cooldown: cooldown) }
    } else {
      await ProcessBudget.shared.release(owner: owner, cooldown: cooldown)
    }
  }

  private static func update<T>(directory: URL, _ operation: (inout State) throws -> T) throws -> T
  {
    let url = directory.appendingPathComponent("coin-metrics-budget.json")
    return try FileCoordination.write(at: url) {
      var state =
        try FileCoordination.dataIfPresent(at: url)
        .map { try JSONDecoder().decode(State.self, from: $0) } ?? State()
      let result = try operation(&state)
      try JSONEncoder().encode(state).write(to: url, options: .atomic)
      return result
    }
  }

  fileprivate static func reserve(_ state: inout State, owner: UUID) -> TimeInterval {
    let now = Date.now
    if let lease = state.lease, lease.expires > now {
      return lease.expires.timeIntervalSince(now)
    }
    let next = max(state.nextStart, state.cooldown)
    if next > now { return next.timeIntervalSince(now) }
    state.nextStart = now.addingTimeInterval(1)
    state.lease = Lease(owner: owner, expires: now.addingTimeInterval(60))
    return 0
  }

  fileprivate static func release(_ state: inout State, owner: UUID, cooldown: Date?) {
    if let cooldown { state.cooldown = max(state.cooldown, cooldown) }
    if state.lease?.owner == owner { state.lease = nil }
  }
}

private actor ProcessBudget {
  static let shared = ProcessBudget()
  private var state = CoinMetricsBudget.State()

  func reserve(owner: UUID) -> TimeInterval {
    CoinMetricsBudget.reserve(&state, owner: owner)
  }

  func release(owner: UUID, cooldown: Date?) {
    CoinMetricsBudget.release(&state, owner: owner, cooldown: cooldown)
  }
}
