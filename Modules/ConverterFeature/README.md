# ConverterFeature

The one-to-many converter experience: amount entry, currency selection and ordering, refresh status, and destination routing. Only `ConverterScreen` is public; its model and supporting views stay internal.

The host supplies details and widget-onboarding destinations, keeping feature implementations independent. The app owns local-currency deep links at its stable root:

```swift
ConverterScreen(store: .shared) { code, reference, snapshot in
  RateDetailsScreen(code: code, reference: reference, snapshot: snapshot, history: history)
} widgets: {
  WidgetOnboardingScreen { LocalCurrencyOnboardingScreen() }
} reconcileLocalCurrency: {
  LocalCurrencyAuthorization.reconcile()
}
```

The feature persists converter edits, refreshes rates while active, and debounces widget reloads. Increment `inputRevision` after a host-owned destination changes saved input; the converter reloads its internal state. Supply an isolated `CurrencyStore` and a configured `RateService` for alternate environments. Link this Tuist target from an iOS 26 SwiftUI app.

The module owns its English string catalog under `Resources`. Xcode generates typed accessors during the build; add translations there rather than editing generated Swift files.

Row taps select an independent `WidgetInput` editor without changing the saved base or currency order. Each accepted key saves the equivalent base amount with Decimal precision; failed writes retain both the saved value and editor. The next digit replaces the selected value, matching widget input. The selected row shows the editable text, including a trailing decimal separator. The keypad header contains only the currency and Done. Removing the active currency clears its editor. Conversion uses the latest saved base inside the coordinated write. Closing the keypad or reloading shared input clears the transient editor.

The active amount uses semibold weight with the normal text color. In portrait, the keypad occupies its own layout space below the scroll view. Selecting a destination or resizing the viewport scrolls the active row into view, including the last row.
