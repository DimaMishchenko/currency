# Widgets

Widget configuration, input state, commands, and persistence. `WidgetsUI` contains reusable production layouts and their resources.

Keep canonical selections independent of widget size. Default widgets share app input; custom widgets retain independent input. Hosts supply button actions, while the executable's native intents and timelines live under [AppExtensions/CurrencyWidgets](../../AppExtensions/CurrencyWidgets).

## History widget

`HistoryWidgetPair` follows the app base and first displayed destination unless overridden. History supports distinct fiat, metal and crypto pairs. Supported crypto 1D charts use sampled intraday references; crypto 1W charts use hourly references when a complete week is available, retaining saved observations or daily fallback otherwise. Converted weekly samples use each UTC day’s approximate FX reference. Fiat-only weeks and longer ranges retain daily/monthly sampling. Crypto timelines request UTC hourly refreshes; WidgetKit controls delivery. The shared latest quote keeps supported crypto widgets and the converter aligned while each chart and percentage retain their selected period. Changes below half a basis point display as neutral. Unsupported or missing history has no synthetic graph. Saved history retains its observation date and is marked in the layout.

`HistoryWidgetView` renders small and medium widgets with the shared rounded typography and currency icons. The full-bleed graph adapts to light, dark, increased-contrast, and accented rendering. The harness and widget extension use the same layout.

## Harness

Select the `WidgetsHarness` scheme and add launch arguments under **Run → Arguments**. Pass the case as the first argument, without `--case`. Omitting it selects `calculator`.

| Case | Behavior |
| --- | --- |
| `calculator` | Medium and large calculator layouts. |
| `calculator-2`, `calculator-4`, `calculator-6`, `calculator-8` | A large Calculator with repeatable mixed fiat, crypto and metal values. Append `-medium`, `-metals`, `-grams` or `-long` for compact, measurement and long-input checks. |
| `board` | Large board layout. |
| `cash` | Cash reference layout. |
| `icon` | Configurable Lock Screen currency-symbol layout. |
| `location` | Calculator layouts with unresolved Local currency. |
| `unavailable` | Calculator layouts with no rate snapshot. |
| `history` | Positive history in medium, small, and dark medium layouts. |
| `history-crypto-freshness` | Production history loading with one hourly endpoint across 1D, 1W, and 1M in light, dark, small, and medium widgets. |
| `history-down` | Negative rate movement. |
| `history-flat` | Neutral line and percentage. |
| `history-tiny` | Small fractional rates retain significant digits. |
| `history-usd-btc` | USD/BTC history from inverted Coin Metrics values, including icon alignment. |
| `history-cached` | Saved-series indicator and original observation date. |
| `history-unavailable` | No available history; no sample data. |
| `history-unsupported` | Identical currencies cannot form a history pair. |
