import Conversion
import ExchangeRates
import Foundation
import Home
import Observation
import Onboarding

/// Scene-owned identities prevent navigation and in-flight feature state leaking between windows.
@MainActor @Observable
public final class CurrencyScene {
  public struct WidgetContext {
    public let snapshot: RateSnapshot
    public let base: String?
    public let quote: String?
    public init(snapshot: RateSnapshot, base: String? = nil, quote: String? = nil) {
      self.snapshot = snapshot; self.base = base; self.quote = quote
    }
  }
  /// One currency-details destination, identified independently of quote refreshes.
  public struct Details: Identifiable, Hashable {
    /// Stable identity for this presentation.
    public let id: UUID
    /// Feature-owned currency and reference values supplied by Home.
    public let request: HomeDetailsRequest
    /// External navigation has no mounted zoom source.
    public var usesZoom: Bool = true
    /// Compares flow identity rather than changing quote data.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    /// Hashes the stable flow identity used by navigation.
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
  }
  /// A scene-owned cross-feature sheet.
  public struct Sheet: Identifiable {
    /// The independently owned feature to present.
    public enum Kind { case widgets }
    /// Stable identity for this presentation.
    public let id: UUID
    /// The feature rendered by application UI.
    public let kind: Kind
  }
  /// A correlated location-onboarding presentation.
  public struct Location: Identifiable {
    /// Stable identity for this presentation.
    public let id: UUID
    /// Whether confirmation also adds the Local selection to confirmed input.
    public let addsToApp: Bool
    /// The requesting widget surface, or nil for application-level presentation.
    public let presenterID: UUID?
  }
  /// Identity used to coordinate this scene with application-lifetime work.
  public let id = UUID()
  /// Identity of the current Home flow.
  public private(set) var homeID = UUID()
  /// Identity of the current onboarding flow.
  public private(set) var onboardingID = UUID()
  /// Whether initial setup still owns the foreground presentation.
  public private(set) var showsOnboarding: Bool
  /// Whether Home can be constructed behind the onboarding finale.
  public private(set) var preloadsHome: Bool
  /// Application-owned navigation destinations with independent flow identities.
  public enum Route: Hashable {
    case settings(UUID)
  }
  /// Scene-local navigation, preserving Settings as a push from Home.
  public var path: [Route] = []
  /// Currency details retain their existing sheet presentation.
  public var detail: Details?
  /// The active widget guide sheet.
  public var sheet: Sheet?
  /// The active location flow and its correlation identity.
  public var location: Location?
  public private(set) var widgetSnapshot: RateSnapshot?
  public private(set) var widgetContextID: UUID?
  private let readWidgetContext: (UUID) -> WidgetContext?
  private let readInput: () -> ConverterState
  private var widgetDetailsID: UUID?
  private var pendingRoute: CurrencyRoute?
  private let openCurrency: (String) -> HomeDetailsRequest?
  private let replay: () throws -> Void
  /// Starts a scene from already-loaded completion state and an explicit replay commit.
  public init(
    completed: Bool, replay: @escaping () throws -> Void,
    readWidgetContext: @escaping (UUID) -> WidgetContext? = { _ in nil },
    readInput: @escaping () -> ConverterState = { ConverterState() },
    openCurrency: @escaping (String) -> HomeDetailsRequest? = { _ in nil }
  ) {
    showsOnboarding = !completed; preloadsHome = completed; self.replay = replay
    self.openCurrency = openCurrency
    self.readWidgetContext = readWidgetContext
    self.readInput = readInput
  }
  /// Interprets synchronous requests from this scene's Home feature.
  public func receive(_ output: HomeOutput) {
    clearWidgetHandoff()
    switch output {
    case .detailsRequested(let request): detail = Details(id: UUID(), request: request)
    case .settingsRequested: path.append(.settings(UUID()))
    case .widgetsRequested: sheet = Sheet(id: UUID(), kind: .widgets)
    case .locationRequested: requestLocation(addsToApp: true)
    }
  }
  /// Rejects completion or preload requests from an onboarding flow replaced by replay.
  public func receive(_ output: OnboardingOutput, flowID: UUID) {
    guard flowID == onboardingID else { return }
    switch output {
    case .finalePresented: preloadsHome = true
    case .completed:
      preloadsHome = true; showsOnboarding = false
      if let route = pendingRoute { pendingRoute = nil; present(route) }
    }
  }
  /// Commits replay before replacing any visible route or feature identity.
  public func restartOnboarding() throws {
    try replay()
    path = []; detail = nil; sheet = nil; location = nil; pendingRoute = nil
    clearWidgetHandoff()
    onboardingID = UUID(); homeID = UUID(); preloadsHome = false; showsOnboarding = true
  }
  /// Starts one location flow without replacing an already active request.
  public func requestLocation(addsToApp: Bool, presenterID: UUID? = nil) {
    guard location == nil else { return }
    clearWidgetHandoff()
    location = Location(id: UUID(), addsToApp: addsToApp, presenterID: presenterID)
  }
  /// Only the requesting surface may present this correlated cross-feature flow.
  public func locationPresented(by presenterID: UUID?) -> Location? {
    guard location?.presenterID == presenterID else { return nil }
    return location
  }
  /// Dismisses only the location flow that produced the matching result.
  public func finishLocation(id: UUID) {
    guard location?.id == id else { return }
    location = nil
  }
  /// Interprets supported application URLs without changing unrelated routes.
  public func open(_ url: URL) {
    guard url.scheme == CurrencyRoute.scheme else { return }
    if url.host == "local-currency" { requestLocation(addsToApp: false); return }
    guard let route = CurrencyRoute(url: url) else { return }
    open(route)
  }
  /// Opens existing content, deferring navigation until this scene finishes onboarding.
  public func open(_ route: CurrencyRoute) {
    if showsOnboarding { pendingRoute = route } else { present(route) }
  }

  public func releaseWidgetSnapshot(id: UUID, snapshot: RateSnapshot) {
    guard widgetContextID == id else { return }
    updateWidgetDetails(snapshot)
    widgetSnapshot = nil
  }

  public func finishWidgetHandoff(id: UUID, snapshot: RateSnapshot? = nil) {
    guard widgetContextID == id else { return }
    if let snapshot { updateWidgetDetails(snapshot) }
    widgetDetailsID = nil
    widgetSnapshot = nil
    widgetContextID = nil
  }

  private func updateWidgetDetails(_ snapshot: RateSnapshot) {
    if let detail, detail.id == widgetDetailsID {
      self.detail = Details(
        id: detail.id,
        request: HomeDetailsRequest(
          selectionID: detail.request.selectionID, code: detail.request.code,
          reference: detail.request.reference, snapshot: snapshot), usesZoom: false)
    }
  }

  private func clearWidgetHandoff() {
    guard widgetContextID != nil else { return }
    if detail?.id == widgetDetailsID { detail = nil }
    widgetSnapshot = nil
    widgetContextID = nil
    widgetDetailsID = nil
    homeID = UUID()
  }

  private func present(_ route: CurrencyRoute) {
    switch route {
    case .widget(let id):
      let context = readWidgetContext(id)
      widgetSnapshot = context?.snapshot
      widgetContextID = context == nil ? nil : id
      path = []; detail = nil; sheet = nil; location = nil
      widgetDetailsID = nil
      homeID = UUID()
      if let context, let base = context.base, let quote = context.quote,
        base != quote, ConversionDestination(code: base).isValid,
        ConversionDestination(code: quote).isValid
      {
        let input = readInput()
        if input.source != base || !input.destinationRows.contains(where: { $0.code == quote }) {
          let destination = Details(
            id: UUID(),
            request: HomeDetailsRequest(
              selectionID: base, code: base, reference: quote, snapshot: context.snapshot),
            usesZoom: false)
          detail = destination
          widgetDetailsID = destination.id
        }
      }
    case .converter:
      clearWidgetHandoff()
      path = []; detail = nil; sheet = nil; location = nil
    case .currency(let id):
      guard let request = openCurrency(id) else { return }
      clearWidgetHandoff()
      path = []; detail = nil; sheet = nil; location = nil
      detail = Details(id: UUID(), request: request, usesZoom: false)
    }
  }
}
