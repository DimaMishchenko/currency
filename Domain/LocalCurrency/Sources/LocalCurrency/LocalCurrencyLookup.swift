/// Progress of the reusable one-shot lookup, independent of any onboarding screen.
public enum LocalCurrencyLookupPhase: Sendable, Equatable {
  case idle, requestingPermission, locating, ready, unavailable
}

/// Domain lookup result or recovery reason; consumers choose their own presentation.
public enum LocalCurrencyLookupOutcome: Sendable, Equatable {
  case none, saved, removed, permissionDenied, permissionRestricted
  case servicesDisabled, unavailable, unsupported, removeFailed, updateFailed
}
