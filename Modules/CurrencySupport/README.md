# CurrencySupport

The app-specific contract shared by the converter and widgets: editable converter state, currency display conventions, recoverable-error text, and App Group storage. This is a Tuist module because its defaults and presentation belong to Currency.

```swift
import CurrencySupport

try CurrencyStore.shared.updateInput { state in
  state.setDestinations(["USD", "GBP", "BTC"])
  state.press("AC")
  state.press("5")
}
```

Use `changeSource` to keep the entered amount, or `useAsBase(_:snapshot:)` to preserve the destination’s converted value, rounded to its display precision. Currency lists are deduplicated and exclude the source. Existing saved input remains compatible.

Use `CurrencyStore.shared` in production and `CurrencyStore(directory:)` for isolated tests or previews. All edits use `updateInput` (or the keypad convenience `press`) to preserve changes made by the other host. Use `loadRates` and `refreshRates(using:force:now:)` for coordinated rate storage. `CurrencyDisplay` supplies names, flags, and formatting; `RateMessages` translates package conditions into app copy.

Generate with `tuist generate --no-open`, then test the `CurrencySupport` scheme on an iOS 26 simulator.

The module owns its English string catalog under `Resources`. Xcode generates typed accessors during the build; add translations there rather than editing generated Swift files.
