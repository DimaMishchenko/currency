# CurrencyWidgets

The extension offers Currency Calculator, Know Your Cash, Pocket Rate, Mental Math, Currency Board and a Lock Screen quick rate. Pair Calculator and fixed legacy lists have been removed; old installations are not migrated.

Calculator starts in Default. It reads the app's ordered source plus destinations and shares its monetary value, while retaining widget input selection and paging. Custom uses the explicit list and widget input storage. The configuration identity is hidden. Native assignment of distinct identities to identical Custom widgets still needs verification; do not equate explicit-key tests with that guarantee. No IDs are generated in timelines or views.

Medium displays the first four entries and large the first eight, without paging. Full lists persist across resizing. Default reserves the last visible slot for Local when enabled; Custom preserves its selected order. Hidden active input is projected into a convertible visible currency without saving the projection until interaction. Without a conversion rate, the original value remains stored and the keypad is disabled until a visible currency is selected. Odd rows keep the final tile left-aligned with an inert right slot. Native editor summaries explain the size limits.

Local remains its own dynamic entry even when its resolved currency duplicates a fixed entry. The location badge identifies it in calculator and reference widgets. Canonical configuration uses `@local`; a resolved display/input identifier such as `@local:CZK` keeps it distinct from fixed CZK. If Local changes currency, active Local input resets safely rather than interpreting the old amount in the new currency.

Board Default follows app base, amount and selected currencies, with no independent base/amount controls. Custom keeps configurable base, amount and targets. Base is a normal bold first slot, with capacities of 4/6/12 total entries for small/medium/large.

Native currency queries show App selected, Location where supported, Currencies, Metals and Crypto sections. Remaining codes are alphabetic, deduplicated, and use leading artwork. Cash restrictions apply.

Location updates are explicit foreground requests. Fresh observations have only the Local badge. A Last-known footer appears after one day or an authorized lookup failure and links to refresh in the app. When Allow Once expires and the app observes Not Determined (delegate or foreground return), it cancels requests and clears the saved observation. There is no supported indication distinguishing Allow Once from persistent When In Use at grant time, and no continuous/background lookup is promised. Permission-off/setup entries use a fully opaque raster background with full-color rendering to resist Home Screen glass/tint transformations. Pocket/Mental widgets retain their container background.

See [implementation evidence and remaining native checks](../Documentation/WidgetImplementationReview.md). The module owns its string catalog under Resources. Build generated accessors instead of editing generated Swift.
