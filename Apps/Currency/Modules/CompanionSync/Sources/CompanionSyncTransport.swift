import Conversion
import Foundation
import Synchronization
import WatchConnectivity

/// Transport failures without exposing vendor error representations.
public enum CompanionSyncIssue: Sendable, Equatable {
  case unsupported, activationFailed, publicationFailed, invalidPayload, commitFailed
}

/// Explicit WatchConnectivity lifetime for one phone publisher or Watch receiver.
@MainActor
public final class CompanionSyncTransport: NSObject, WCSessionDelegate {
  /// Phone preferences flow to Watch; Watch never publishes preference changes.
  public enum Role: Sendable, Equatable { case phone, watch }
  /// Most recent transport or acceptance failure.
  public private(set) var issue: CompanionSyncIssue?
  private let role: Role
  private let engine: CompanionSyncEngine
  private let session: WCSession
  private var started = false
  private nonisolated let lifetime = Mutex<UUID?>(nil)
  private nonisolated static let payloadKey = "currency.favorites.v1"

  /// Constructs an inactive transport; the executable decides when activation begins.
  public init(role: Role, engine: CompanionSyncEngine, session: WCSession = .default) {
    self.role = role
    self.engine = engine
    self.session = session
    super.init()
  }

  /// Activates the session once; unsupported hosts report an issue without starting work.
  public func start() {
    guard !started else { return }
    guard WCSession.isSupported() else { issue = .unsupported; return }
    lifetime.withLock { $0 = UUID() }
    started = true
    session.delegate = self
    session.activate()
  }

  /// Retries the latest Watch context on foreground entry without restarting the session.
  public func reconcile() {
    guard started, role == .watch, session.activationState == .activated else { return }
    receive(session.receivedApplicationContext)
  }

  /// Persists phone favorites and publishes the latest context when the session is activated.
  public func publish(_ input: ConverterState) throws {
    guard role == .phone else { return }
    _ = try engine.phoneContext(for: input)
    flush()
  }

  /// Detaches this transport and rejects subsequently delivered delegate work.
  public func stop() {
    started = false
    lifetime.withLock { $0 = nil }
    if session.delegate === self { session.delegate = nil }
  }

  private func flush() {
    guard started, role == .phone, session.activationState == .activated,
      let context = engine.outgoing
    else { return }
    do {
      let data = try JSONEncoder().encode(context)
      try session.updateApplicationContext([Self.payloadKey: data])
      issue = nil
    } catch { issue = .publicationFailed }
  }

  /// Activation completion retries the latest durable publication or receives the current Watch context.
  public nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: (any Error)?
  ) {
    let succeeded = activationState == .activated && error == nil
    let identity = lifetime.withLock { $0 }
    Task { @MainActor [weak self] in
      guard let self, self.started, let identity,
        self.lifetime.withLock({ $0 }) == identity
      else { return }
      if succeeded {
        self.issue = nil
        self.flush()
        self.reconcile()
      } else {
        self.issue = .activationFailed
      }
    }
  }

  /// Contexts delivered after stop or from an earlier lifetime are ignored.
  public nonisolated func session(
    _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    let context = (applicationContext[Self.payloadKey] as? Data)
      .flatMap { try? JSONDecoder().decode(CompanionFavoritesContext.self, from: $0) }
    let identity = lifetime.withLock { $0 }
    Task { @MainActor [weak self] in
      guard let self, self.started, self.role == .watch, let identity,
        self.lifetime.withLock({ $0 }) == identity
      else { return }
      self.accept(context)
    }
  }

  private func receive(_ applicationContext: [String: Any]) {
    guard !applicationContext.isEmpty else { return }
    let context = (applicationContext[Self.payloadKey] as? Data)
      .flatMap { try? JSONDecoder().decode(CompanionFavoritesContext.self, from: $0) }
    accept(context)
  }

  private func accept(_ context: CompanionFavoritesContext?) {
    guard let context else { issue = .invalidPayload; return }
    do {
      _ = try engine.accept(context)
      issue = nil
    } catch is CompanionSyncError { issue = .invalidPayload } catch { issue = .commitFailed }
  }

  #if os(iOS)
    /// Required transition callback when the active paired Watch changes.
    public nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Pairing changes reactivate the session only while this transport remains started.
    public nonisolated func sessionDidDeactivate(_ session: WCSession) {
      let identity = lifetime.withLock { $0 }
      Task { @MainActor [weak self] in
        guard let self, self.started, let identity,
          self.lifetime.withLock({ $0 }) == identity
        else { return }
        self.session.activate()
      }
    }
  #endif
}
