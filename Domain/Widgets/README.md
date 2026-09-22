# Widgets

Widget configuration, input state, commands, and persistence. `WidgetsUI` contains reusable production layouts and their resources.

Keep canonical selections independent of widget size. Default widgets share app input; custom widgets retain independent input. Hosts supply button actions, while the executable's native intents and timelines live under [App/Widgets](../../App/Widgets).

## History widget

`HistoryWidgetPair` follows the app base and first displayed destination unless overridden. `HistoryWidgetSnapshot` derives the value, observation date, and percentage change from one historical series; it never mixes current quotes with historical endpoints. Changes below half a basis point display as neutral. Unsupported or missing history has no synthetic graph. Saved history retains its original observation date and is marked in the layout.

`HistoryWidgetView` renders small and medium widgets with the shared rounded typography and currency icons. The full-bleed graph adapts to light, dark, increased-contrast, and accented rendering. The harness and widget extension use the same layout.

## Harness

Select the `WidgetsHarness` scheme and add launch arguments under **Run → Arguments**. Pass the case as the first argument, without `--case`. Omitting it selects `calculator`.

| Case | Behavior |
| --- | --- |
| `calculator` | Medium and large calculator layouts. |
| `board` | Large board layout. |
| `cash` | Cash reference layout. |
| `icon` | Configurable Lock Screen currency-symbol layout. |
| `location` | Calculator layouts with unresolved Local currency. |
| `unavailable` | Calculator layouts with no rate snapshot. |
| `history` | Positive history in medium, small, and dark medium layouts. |
| `history-down` | Negative rate movement. |
| `history-flat` | Neutral line and percentage. |
| `history-tiny` | Small fractional rates retain significant digits. |
| `history-cached` | Saved-series indicator and original observation date. |
| `history-unavailable` | No available history; no sample data. |
| `history-unsupported` | Unsupported cryptocurrency comparison. |
