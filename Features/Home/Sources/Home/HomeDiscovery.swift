import Foundation

/// The converter control highlighted by discovery.
public enum HomeDiscoveryTip: Sendable, Equatable {
  case history, widgets
}

/// Durable converter learning state independent of TipKit presentation.
public struct HomeDiscoveryProgress: Codable, Sendable, Equatable {
  /// The first completed Home observation, used as the widget delay anchor.
  public var firstObservedAt: Date?
  /// Number of editing sessions that ended with a changed numeric amount.
  public var completedEdits = 0
  /// Whether currency details or history have been opened.
  public var visitedDetails = false
  /// Whether the toolbar widget guide has been opened.
  public var openedWidgets = false
  /// Whether the history tip appeared.
  public var showedHistoryTip = false
  /// Whether the widgets tip appeared.
  public var showedWidgetsTip = false

  /// Creates a user with no converter discovery history.
  public init() {}

  /// Offers history after one prior meaningful edit and before visiting details.
  public func canOfferHistory(editing: Bool) -> Bool {
    editing && completedEdits > 0 && !visitedDetails && !showedHistoryTip
  }

  /// Offers widgets only after a later-day useful edit and without competing discovery.
  public func canOfferWidgets(
    now: Date, calendar: Calendar = .current, closedWithResults: Bool, firstHomeVisit: Bool,
    historyShownThisVisit: Bool
  ) -> Bool {
    guard let firstObservedAt else { return false }
    return calendar.startOfDay(for: now) > calendar.startOfDay(for: firstObservedAt)
      && closedWithResults && !firstHomeVisit && !historyShownThisVisit
      && !openedWidgets && !showedWidgetsTip
  }
}
