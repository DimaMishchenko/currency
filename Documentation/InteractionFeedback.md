# Loading and tactile feedback

The first-launch bootstrap and converter pull-to-refresh share `CurrencySymbolLoader`: a fixed optical box cycling through euro, pound, yen, and dollar SF Symbols. Both use the original SF Symbols Magic Replace transition with a standard replacement fallback. Refresh renders one symbol at a time rather than overlapping two translucent glyphs. Reduce Motion stops symbol movement, and inactive scenes stop refresh presentation.

The converter attaches a native `UIRefreshControl` inside its scroll content. UIKit owns the trigger, inset, and rebound, so the loader occupies the space above the first row. The first native symbol replacement starts immediately when pulling reveals the loader, then continues through loading with 400 ms between replacements. Bootstrap keeps its original delayed first transition. Pull distance controls only visibility. Presentation lasts at least 1.1 seconds, waits for an active drag to end, then fades over 250 ms before UIKit collapses the inset. Rate data applies immediately. Accessibility refresh and Options provide non-drag alternatives. Detaching cancels the presentation and work; model cancellation clears the indicator without reporting an error.

## Interaction vocabulary

| Interaction | Feedback |
| --- | --- |
| Currency selection, categories, reorder, changed keypad digits | Light selection tick |
| Open/close a destination, amount editor, widget guide controls | Medium action tap at 85% intensity |
| Remove currency, delete digit | Full medium impact |
| Swap base currency, onboarding step, resize widget preview | Custom two-beat settle, 180 ms apart |
| Onboarding finale | Custom rising three-beat sequence over 350 ms |
| Copy amount, manual rate refresh succeeds, saved manual currency, onboarding completion, resolved local currency | Success notification |
| Partial/offline rate result, unavailable history | Warning notification |
| Persistence failure or failed location request | Error notification |
| Chart scrub across data points | Selection ticks capped at one per 55 ms |
| Finale and location tutorial orbits during drag and user momentum | Native selection ticks every 7.5 degrees, capped at one per 22 ms; decorative drift stays silent |
| History chart drawing | Custom seven-beat sequence following the 550 ms ease-out; cancels when the chart closes or a new interaction begins |

`AppHaptics` owns the vocabulary. New cues stop pending custom patterns, inactive scenes stop playback, and unsupported Core Haptics hardware falls back to system feedback. Reduce Motion substitutes a single system cue for custom sequences. Automatic converter refreshes and decorative looping animations stay silent. Widget previews provide feedback in the app; WidgetKit extension actions do not attempt to operate the app's haptic engine.

The interaction review also exposed save-error text hidden behind the currency-management sheet. The sheet now displays the model's warning. Failed converter mutations return false so they cannot trigger a successful swap/delete cue; unchanged keypad values don't generate a selection tick.

## Orbit behavior

The location illustration shares `CurrencyOrbitMotion` with the finale. Dragging grabs the current angle and releasing preserves momentum; changing location-request speed preserves position. Reduce Motion disables location-orbit drift and inertia but retains direct manipulation. VoiceOver provides adjustable rotation, and leaving the location view or backgrounding cancels momentum.

## Validation (2026-09-19)

- Fresh-context subagent reviewed all modified and new Swift files. Two minor duplicate-cue findings in currency selection and widget tutorial completion were fixed and re-reviewed; no findings remain.
- 44 ExchangeRates package tests, 41 CurrencySupport tests, and 64 integration tests passed. Coverage includes refresh attachment recovery after scroll-view reconfiguration, scene reactivation, stable pull visibility across native inset changes, cancellation, failed saves, orbit drift changes, and user momentum ending while decorative drift continues.
- Debug and Release app/widget simulator builds passed.
- Strict Swift formatting and `git diff --check` passed for all changed Swift files.
- Isolated iPhone 17 Pro / iOS 26.5 validation covered first-run currency selection, widget showcase, finale, converter editing and swaps, and refresh. Refresh recordings with five currencies were inspected through pull, loading, fade, and rebound. The final loader uses immediate native symbol replacement every 400 ms; normal-speed recordings were shared for user review.
- Actual vibration strength, sharpness, and subjective feel require an iPhone. Simulator results do not establish tactile quality, real-device permission behavior, or Home Screen widget feedback.
