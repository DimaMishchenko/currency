# Currency Watch widgets

watchOS 26 extension with Pocket Rate, Currency Board, History, Mental Math,
Know Your Cash, Currency Icon, Favorite Pairs, and an Open Currency control.
Rectangular widgets appear on watch faces and in the Smart Stack; circular, inline,
and corner families provide compact face presentations. Favorite Pairs uses the
native rectangular `AccessoryWidgetGroup`.

The executable supplies the Watch App Group directory to `ConversionStore`,
`RateStore`, `WidgetStore`, and `HistoryService`. Missing entitlement fails explicitly.
Empty currency choices follow the Watch source and favorites; Local is excluded.
Know Your Cash offers only fiat and metals. An ineligible followed source uses EUR;
its comparison uses the first eligible distinct favorite, then USD (EUR for a USD source).
Unsupported saved cash pairs prompt a new currency or metal selection.
Rates load from cache before refresh, and historical graphs use real validated series.

Pocket Rate's presets and swap persist independently of the app's converter. Records
use the widget kind, source, comparison currencies, and configured amount as a stable
key. Identical configurations share amount and swap state across placements.

Routes are `currency-watch://convert` and `currency-watch://details`, with `source`
and `quote`; only conversion accepts `amount`. Missing or invalid pairs open the converter
without replacing its input. The app owns routing. Add Open Currency
through Control Center's Edit gallery; tapping it brings the Watch app to the foreground.

Copy uses generated symbols from `WatchWidgets.xcstrings`, translated in 14 languages.
