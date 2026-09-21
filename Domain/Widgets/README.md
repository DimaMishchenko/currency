# Widgets

Widget configuration, input state, commands, and persistence. `WidgetsUI` contains reusable production layouts and their resources.

Keep canonical selections independent of widget size. Default widgets share app input; custom widgets retain independent input. Hosts supply button actions, while the executable's native intents and timelines live under [App/Widgets](../../App/Widgets).

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
