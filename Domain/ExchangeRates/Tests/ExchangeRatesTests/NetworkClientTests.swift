import Foundation
import Testing

@testable import ExchangeRates

private final class ControlledProtocol: URLProtocol, @unchecked Sendable {
  final class State: @unchecked Sendable {
    let lock = NSLock()
    var requests: [URLRequest] = []
    var starts: [URL: ContinuousClock.Instant] = [:]
    var active: [ControlledProtocol] = []
    var stopped = 0

    func start(_ loader: ControlledProtocol) {
      lock.withLock {
        requests.append(loader.request)
        if let url = loader.request.url { starts[url] = ContinuousClock().now }
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

    func startTime(_ url: URL) -> ContinuousClock.Instant? {
      lock.withLock { starts[url] }
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

@Suite(.serialized) struct CoinbaseTransportTests {
  private func setup() -> (NetworkClient, URLSession) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ControlledProtocol.self]
    let session = URLSession(configuration: config)
    return (NetworkClient(timeout: 7, session: session), session)
  }

  private func url(
    host: String = "api.exchange.coinbase.com", path: String = "/products/BTC-USD/candles"
  ) throws -> URL {
    try #require(URL(string: "https://\(host)\(path)?request=\(UUID().uuidString)"))
  }

  @Test func separateTransportsPaceCandlesWhileOtherEndpointsComplete() async throws {
    let (firstClient, firstSession) = setup()
    let (secondClient, secondSession) = setup()
    defer {
      firstSession.invalidateAndCancel()
      secondSession.invalidateAndCancel()
    }
    let firstURL = try url()
    let secondURL = try url(path: "/products/ETH-USD/candles")
    let thirdURL = try url(path: "/products/BTC-EUR/candles")
    let tickerURL = try url(path: "/products/BTC-USD/ticker")
    let otherHostURL = try url(host: "example.test")
    let first = Task { try await firstClient.get(firstURL) }
    defer { first.cancel() }
    try await waitUntil { ControlledProtocol.state.count(firstURL) == 1 }
    let requests = [
      (secondClient, secondURL), (firstClient, thirdURL),
      (firstClient, tickerURL), (secondClient, otherHostURL)
    ]
    let tasks = requests.map { client, url in Task { try await client.get(url) } }
    defer { for task in tasks { task.cancel() } }
    try await waitUntil {
      ControlledProtocol.state.count(tickerURL) == 1
        && ControlledProtocol.state.count(otherHostURL) == 1
    }
    ControlledProtocol.state.reply(tickerURL)
    ControlledProtocol.state.reply(otherHostURL)
    for task in tasks.suffix(2) { #expect(try await task.value == Data("response".utf8)) }
    try await waitUntil {
      ControlledProtocol.state.count(secondURL) == 1
        && ControlledProtocol.state.count(thirdURL) == 1
    }
    let starts = try [firstURL, secondURL, thirdURL]
      .map {
        try #require(ControlledProtocol.state.startTime($0))
      }
      .sorted()
    #expect(starts[0].duration(to: starts[1]) >= .milliseconds(100))
    #expect(starts[1].duration(to: starts[2]) >= .milliseconds(100))
    for requestURL in [firstURL, secondURL, thirdURL] {
      ControlledProtocol.state.reply(requestURL)
    }
    #expect(try await first.value == Data("response".utf8))
    for task in tasks.prefix(2) { #expect(try await task.value == Data("response".utf8)) }
  }
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
