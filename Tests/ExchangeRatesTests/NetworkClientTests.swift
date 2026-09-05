import Foundation
import Testing

@testable import ExchangeRates

private final class ControlledProtocol: URLProtocol, @unchecked Sendable {
  final class State: @unchecked Sendable {
    let lock = NSLock()
    var requests: [URLRequest] = []
    var active: [ControlledProtocol] = []
    var stopped = 0

    func start(_ loader: ControlledProtocol) {
      lock.withLock {
        requests.append(loader.request)
        active.append(loader)
      }
    }

    func stop(_ loader: ControlledProtocol) {
      lock.withLock {
        active.removeAll { $0 === loader }
        stopped += 1
      }
    }

    func count(_ url: URL) -> Int {
      lock.withLock { requests.filter { $0.url == url }.count }
    }

    func reply(_ url: URL, status: Int = 200) {
      let loaders = lock.withLock {
        let result = active.filter { $0.request.url == url }
        active.removeAll { $0.request.url == url }
        return result
      }
      for loader in loaders {
        guard
          let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else {
          Issue.record("Invalid mock HTTP response")
          continue
        }
        loader.client?.urlProtocol(loader, didReceive: response, cacheStoragePolicy: .notAllowed)
        loader.client?.urlProtocol(loader, didLoad: Data("response".utf8))
        loader.client?.urlProtocolDidFinishLoading(loader)
      }
    }
  }

  static let state = State()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { Self.state.start(self) }
  override func stopLoading() { Self.state.stop(self) }
}

private func waitUntil(_ predicate: () -> Bool) async throws {
  for _ in 0..<200 {
    if predicate() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  try #require(predicate())
}

@Suite struct NetworkClientTests {
  private func setup() throws -> (NetworkClient, URLSession, URL) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ControlledProtocol.self]
    let session = URLSession(configuration: config)
    return (
      NetworkClient(timeout: 7, session: session), session,
      try #require(URL(string: "https://example.test/\(UUID().uuidString)"))
    )
  }

  @Test func overlappingRequestsShareTransferAndLaterCallsRefetch() async throws {
    let (client, session, url) = try setup()
    defer { session.invalidateAndCancel() }
    let first = Task { try await client.get(url) }
    let second = Task { try await client.get(url) }
    try await waitUntil { ControlledProtocol.state.count(url) == 1 }
    try await Task.sleep(for: .milliseconds(50))
    #expect(ControlledProtocol.state.count(url) == 1)
    ControlledProtocol.state.reply(url)
    #expect(try await first.value == Data("response".utf8))
    #expect(try await second.value == Data("response".utf8))
    let later = Task { try await client.get(url) }
    try await waitUntil { ControlledProtocol.state.count(url) == 2 }
    ControlledProtocol.state.reply(url)
    _ = try await later.value
    let request = try #require(
      ControlledProtocol.state.lock.withLock {
        ControlledProtocol.state.requests.first { $0.url == url }
      })
    #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    #expect(request.timeoutInterval == 7)
  }

  @Test func cancellingOneWaiterDoesNotCancelAnother() async throws {
    let (client, session, url) = try setup()
    defer { session.invalidateAndCancel() }
    let first = Task { try await client.get(url) }
    let second = Task { try await client.get(url) }
    try await waitUntil { ControlledProtocol.state.count(url) == 1 }
    try await Task.sleep(for: .milliseconds(50))
    first.cancel()
    do {
      _ = try await first.value
      Issue.record("Cancelled waiter succeeded")
    } catch { #expect(error is CancellationError) }
    ControlledProtocol.state.reply(url)
    #expect(try await second.value == Data("response".utf8))
    #expect(ControlledProtocol.state.count(url) == 1)
  }

  @Test func lastCancellationStopsTransferAndAllowsNewRequest() async throws {
    let (client, session, url) = try setup()
    defer { session.invalidateAndCancel() }
    let first = Task { try await client.get(url) }
    try await waitUntil { ControlledProtocol.state.count(url) == 1 }
    first.cancel()
    _ = await first.result
    try await waitUntil {
      ControlledProtocol.state.lock.withLock {
        !ControlledProtocol.state.active.contains { $0.request.url == url }
      }
    }
    let second = Task { try await client.get(url) }
    try await waitUntil { ControlledProtocol.state.count(url) == 2 }
    ControlledProtocol.state.reply(url)
    #expect(try await second.value == Data("response".utf8))
  }

  @Test func httpFailureIsNotRetriedOrCached() async throws {
    let (client, session, url) = try setup()
    defer { session.invalidateAndCancel() }
    let first = Task { try await client.get(url) }
    try await waitUntil { ControlledProtocol.state.count(url) == 1 }
    ControlledProtocol.state.reply(url, status: 429)
    do {
      _ = try await first.value
      Issue.record("HTTP 429 succeeded")
    } catch RateError.http(let status) { #expect(status == 429) }
    let next = Task { try await client.get(url) }
    try await waitUntil { ControlledProtocol.state.count(url) == 2 }
    ControlledProtocol.state.reply(url)
    _ = try await next.value
  }
}
