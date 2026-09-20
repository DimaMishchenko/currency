import Foundation

/// Errors produced while loading or validating rate data.
public enum RateError: Error {
  /// A response or persisted payload violates the expected data contract.
  case invalidData
  /// A server returned an unsuccessful HTTP status code.
  case http(Int)
  /// No configured source could provide usable data.
  case unavailable
}

/// An asynchronous HTTP data loader.
public protocol HTTPClient: Sendable {
  /// Returns response data, throwing on transport failures or unsuccessful HTTP status codes.
  func get(_ url: URL) async throws -> Data
}

/// A pooled URLSession client with shared in-flight GETs and cancellation per caller.
/// Application snapshots own freshness; HTTP responses never silently reuse local cached data.
public struct NetworkClient: HTTPClient {
  private let timeout: TimeInterval
  private let transport: HTTPTransport
  private static let shared = HTTPTransport(
    session: {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.urlCache = nil
      configuration.httpCookieStorage = nil
      configuration.httpShouldSetCookies = false
      configuration.timeoutIntervalForResource = 45
      configuration.waitsForConnectivity = false
      return URLSession(configuration: configuration)
    }())

  /// Creates a client with an inactivity timeout. The shared transport caps transfers at 45 seconds.
  /// Supply a session to customize transport configuration or intercept requests in tests.
  public init(timeout: TimeInterval = 12, session: URLSession? = nil) {
    self.timeout = timeout
    transport = session.map { HTTPTransport(session: $0) } ?? Self.shared
  }

  /// Loads and validates a response, sharing identical active requests within this process.
  public func get(_ url: URL) async throws -> Data {
    let data = try await transport.get(url, timeout: timeout)
    try Task.checkCancellation()
    return data
  }
}

private actor HTTPTransport {
  struct Key: Hashable {
    let url: URL
    let timeout: TimeInterval
  }

  struct Pending {
    let id: UUID
    let task: Task<Void, Never>
    var waiters: [UUID: CheckedContinuation<Data, any Error>]
  }

  let session: URLSession
  var pending: [Key: Pending] = [:]

  init(session: URLSession) { self.session = session }

  func get(_ url: URL, timeout: TimeInterval) async throws -> Data {
    let key = Key(url: url, timeout: timeout)
    let waiter = UUID()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        if pending[key] != nil {
          pending[key]?.waiters[waiter] = continuation
          return
        }
        let id = UUID()
        let task = Task {
          let result: Result<Data, any Error>
          do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = timeout
            request.setValue(
              "application/json, application/xml, text/xml", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw RateError.invalidData }
            guard (200..<300).contains(response.statusCode) else {
              throw RateError.http(response.statusCode)
            }
            result = .success(data)
          } catch { result = .failure(error) }
          finish(key, id: id, result: result)
        }
        pending[key] = Pending(id: id, task: task, waiters: [waiter: continuation])
      }
    } onCancel: {
      Task { await self.cancel(key, waiter: waiter) }
    }
  }

  private func finish(_ key: Key, id: UUID, result: Result<Data, any Error>) {
    guard let request = pending[key], request.id == id else { return }
    pending[key] = nil
    for waiter in request.waiters.values { waiter.resume(with: result) }
  }

  private func cancel(_ key: Key, waiter: UUID) {
    guard let continuation = pending[key]?.waiters.removeValue(forKey: waiter) else { return }
    continuation.resume(throwing: CancellationError())
    if pending[key]?.waiters.isEmpty == true {
      pending.removeValue(forKey: key)?.task.cancel()
    }
  }
}
