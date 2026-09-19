# Local currency — September 19, 2026

Local is a persistent selection in the app and synchronized widgets. Its ISO currency resolves from the shared permitted observation; ordinary manually selected currencies remain independent. Stale results are labelled, and unavailable results open permission/retry recovery. There is no manual location fallback.

The app checks for a due refresh while active. Location-enabled widgets check during eligible timeline runs using `NSWidgetWantsLocation` and `isAuthorizedForWidgetUpdates`. Successful observations are fresh for 24 hours, with automatic failure retries limited to once an hour. WidgetKit controls actual runtime; this is not a guaranteed daily background job. Permission is never requested automatically.

The tutorial has one primary action and a small privacy caption at the bottom. The Change/Clear menu is removed. The converter identifies Local with a location icon in its currency row; there is no automatic-update footer for a fresh result. Stale and unavailable results retain their recovery links. Local can be removed from the converter's currency-management list; location permission is managed in Settings.

## Validation

- 73 integration tests passed, including permission recovery, no automatic prompt, failure throttling, concurrent lookup ordering, and preserving a valid amount editor during location reloads.
- 47 CurrencySupport tests passed (55 parameterized executions), including dynamic Local persistence, permission loss, daily freshness, shared refresh claims, and rejection of older lookup results.
- Debug and Release app/widget builds passed. Strict Swift formatting, localization JSON validation, and `git diff --check` passed.
- Three iterative subagent review passes; all reported correctness findings fixed, with no remaining actionable P1/P2 findings or newly introduced dead code in the final pass.
- Native iOS 26.5 simulator: initial permission screen, small bottom privacy caption, successful Czech Koruna lookup, dynamic Local selection alongside an existing CZK row, denied permission, Settings recovery, and automatic British Pound resolution after restoring permission with a synthetic London location.
- Rendered small and medium Board widgets with resolved Local and denied permission. Local displays the ISO code, location marker, and converted value, or the recovery link. The temporary rendering harness was removed after inspection.
- Rendered large Calculator widgets and their dense previews with seven and eight currencies in light and dark appearance. Local follows the same compact layout as other currencies, replacing its hidden currency header with a small location badge on the flag so amounts remain aligned. The focused rendering test passed; its temporary harness was removed after inspection.
- Follow-up: all resolved Local markers in Calculator, Board, Cash, Pocket Rate, and Mental Math use the shared `WidgetCurrencyIcon`: a small secondary-colored arrow beside the flag, without a circular background or a duplicate arrow beside the currency code. Nine representative layouts were rendered in both light and dark appearance and inspected; the focused rendering test passed and its temporary harness was removed. Permission/retry prompts remain unchanged.
- Final pre-commit review covered the complete Local selection, refresh, recovery, and widget changes, with no new actionable P1/P2 findings. Both complete test suites and the Release app/widget build were rerun successfully after the marker refinement; strict formatting, plist validation, and diff checks passed.

The dedicated simulator was `Currency Location Review` (`079290F0-FBF1-46DC-90B6-55A0F1DA6805`). Debug uses bundle ID `com.dimasike.currency.d`; Release uses `com.dimasike.currency`. Target the matching identifier when changing simulator permissions.

Physical-device widget visibility, permission eligibility, and multi-day scheduling remain device validation items; simulator tests cannot establish an exact delivery cadence.
