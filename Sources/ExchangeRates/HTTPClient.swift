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
/// The URLSession-backed HTTP client.
public struct NetworkClient: HTTPClient {
  private let timeout: TimeInterval
  /// Creates a client with a request timeout.
  public init(timeout: TimeInterval = 12) { self.timeout = timeout }
  /// Loads data from a URL and validates its HTTP status.
  public func get(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = timeout
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw RateError.invalidData }
    guard (200..<300).contains(response.statusCode) else {
      throw RateError.http(response.statusCode)
    }
    return data
  }
}
