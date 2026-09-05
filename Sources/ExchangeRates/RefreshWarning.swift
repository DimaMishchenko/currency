/// A recoverable refresh condition that the host can present in its own language.
public enum RefreshWarning: Sendable, Equatable {
  /// Both daily feeds failed; any saved daily quotes remain in use.
  case dailyRatesUnavailable
  /// Some supported cryptocurrencies could not obtain an intraday quote.
  case partialCryptoFallback
}
