# ConverterFeature

The one-to-many converter experience: amount entry, currency selection and ordering, refresh status, and destination routing. Only `ConverterScreen` is public; its model and supporting views stay internal.

The host supplies details and onboarding destinations, keeping feature implementations independent:

```swift
ConverterScreen(store: .shared) { code, reference, snapshot in
  RateDetailsScreen(code: code, reference: reference, snapshot: snapshot, history: history)
} widgets: {
  WidgetOnboardingScreen { LocalCurrencyOnboardingScreen() }
} localCurrency: {
  LocalCurrencyOnboardingScreen()
} reconcileLocalCurrency: {
  LocalCurrencyAuthorization.reconcile()
}
```

The feature persists converter edits, refreshes rates while active, and debounces widget reloads. Supply an isolated `CurrencyStore` and a configured `RateService` for alternate environments. Link this Tuist target from an iOS 26 SwiftUI app.

The module owns its English string catalog under `Resources`. Xcode generates typed accessors during the build; add translations there rather than editing generated Swift files.
