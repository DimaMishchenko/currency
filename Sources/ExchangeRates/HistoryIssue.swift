/// A recoverable condition encountered while loading a historical series.
public enum HistoryIssue: Sendable, Equatable {
  /// The provider cannot serve the requested pair.
  case unsupportedPair
  /// No usable series is available from the network or cache.
  case unavailable
  /// Refresh failed and a previously saved series is returned.
  case usingCachedSeries
  /// Fresh history is returned, but could not be persisted.
  case cacheWriteFailed
}
