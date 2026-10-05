# Currency Watch widgets

watchOS 26 extension with Pocket Rate, Currency Board, History, Mental Math,
Know Your Cash, Favorite Pairs, and an Open Currency control.
Rectangular widgets appear on watch faces and in the Smart Stack; circular and inline
families provide compact face presentations. Pocket Rate is the only corner widget,
curving both compact amounts above the currency names with a single arrow. Favorite
Pairs centers its source above three destination links. Ordinary update timestamps are omitted;
unavailable, stale and daily fallback rates retain compact accessible indicators.

The executable supplies the Watch App Group directory to `ConversionStore`,
`RateStore`, `WidgetStore`, and `HistoryService`. Missing entitlement fails explicitly.
Empty currency choices follow the Watch source and favorites; Local is excluded.
Know Your Cash offers only fiat and metals. Its denomination buttons select banknotes
or gram weights and update one prominent conversion. An ineligible followed source uses EUR;
its comparison uses the first eligible distinct favorite, then USD (EUR for a USD source).
Unsupported saved cash pairs prompt a new currency or metal selection.
Rates load from cache before refresh, and historical graphs use real validated series.
Snapshots respect configured currencies, amounts and history ranges, including the native
editor. History snapshots read saved series without network requests; timeline refreshes
load current history. Only placeholders and SwiftUI previews use fixed sample pairs.
See [simulator signing](../../Apps/CurrencyWatch/README.md) before verifying entity configuration.

Pocket Rate and Know Your Cash setup choose currencies only; their buttons select
amounts. Board and Favorite Pairs retain a configurable amount. Widget button state
persists independently of the app's converter. Metal amounts, rates, labels and history
follow the Watch app's saved troy-ounce, gram or kilogram measurement. Know Your Cash
retains the same gram presets as iOS; opening its conversion preserves physical mass
in the app's selected unit. Changes of measurement preserve existing widget quantities. Records use the widget kind, source,
comparison currencies, and initial amount as a stable key. Identical configurations share amount and swap state across placements.

Routes are `currency-watch://convert` and `currency-watch://details`, with `source`
and `quote`; only conversion accepts `amount` and optional `metalUnit` (`troyOunce`,
`gram`, or `kilogram`). Metal widget links carry the amount's measurement so opening
an older timeline preserves physical mass after the app preference changes. Cash links
carry grams. Missing or invalid pairs open the converter
without replacing its input. The app owns routing. Add Open Currency
through Control Center's Edit gallery; tapping it brings the Watch app to the foreground.

Copy uses generated symbols from `WatchWidgets.xcstrings`, translated in 14 languages.
