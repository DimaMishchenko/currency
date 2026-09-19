# Direct currency editing — September 19, 2026

The base changes only through the top-left currency picker. Tapping a result opens its editor in one step and leaves the ordered list intact. The active amount uses semibold weight with its normal text color. Closing the keypad clears the active styling.

The portrait keypad occupies real layout space below the list. After expansion or a viewport resize, the active result scrolls into view. The final row uses bottom alignment so its complete amount remains above the keypad. Closing the keypad restores the normal viewport and clamps the scroll offset; no artificial bottom spacer is added.

Verified on an isolated iPhone 17 Pro simulator running iOS 26.5:

- Editing USD and GBP directly, switching rows with the keypad open, decimal entry, Done, persistence after relaunch, and manual base selection.
- Editing the last Bitcoin row keeps its full row above the keypad; closing the keypad restores the ordinary list with zero extra offset when all rows fit.
- Actual rendered frames verified the semibold-only active amount, normal text color, and fixed horizontal row insets during automatic scrolling.
- App and widget Debug build passed. Integration suite passed after review fixes (69 test executions), including the repeating-decimal, active-row removal, concurrent base change, and failed-save regression tests.
- Strict Swift formatting and `git diff --check` passed.

Regression coverage includes stable base and ordering, persistence, failed writes retaining the editor, missing quotes, source editing, and switching rows after a base conversion produces more than 30 characters of decimal text.

The keypad header contains only the currency and Done; the follow-up screenshot verifies removal of the duplicated amount. Regression tests also cover removal of the active row and edits after a concurrent base change.

The earlier video `currency-direct-editing-final-2026-09-19.mp4` demonstrates the row styling, bottom-row entry, row switching, keypad dismissal, and explicit base selection. Physical-device haptics and VoiceOver speech were not tested; selected traits, action labels, and an independently accessible Done control were inspected through accessibility output.
