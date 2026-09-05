# RateDetailsFeature

Current conversion provenance and historical charts for a selected currency. `RateDetailsScreen` is the sole public entry point and can be presented as a sheet by any app feature.

```swift
RateDetailsScreen(
  code: "BTC", reference: "EUR", snapshot: snapshot,
  history: HistoryService(directory: cacheDirectory)
)
```

Supply the current snapshot and a history service configured by the host. The screen loads ranges on demand, cancels superseded requests, and presents cached/unavailable states. Crypto charts use USD; fiat charts use the selected reference when supported. Link this Tuist target from an iOS 26 SwiftUI app.

The module owns its English string catalog under `Resources`. Xcode generates typed accessors during the build; add translations there rather than editing generated Swift files.
