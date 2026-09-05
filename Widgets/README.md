# CurrencyWidgets

The WidgetKit extension provides independently configured calculators, cash and mental-math references, Currency Board, and a quick-rate Lock Screen widget. New calculator widgets receive a persisted, hidden UUID and keep independent input, even with identical currencies. The native editor exposes only currency settings. Resizing preserves the full configured list and input; medium calculators show the fixed group of up to four currencies containing the active currency. Never generate an identity in a timeline or view. Comparison pickers offer Local currency first. Board settings can switch between a custom list and default currencies.

Build and run the `Currency` app, then add a Currency widget from the Home Screen or Lock Screen gallery. App and extension must share the configured App Group. Keep simulator signing enabled when testing storage integration.

This executable exposes no library API. It consumes `CurrencySupport` and `ExchangeRates`; iOS controls timeline scheduling and interactive update timing. Keypad intents persist input before returning; WidgetKit then reloads the interacted widget. Digits avoid rate reads, and timelines immediately following input use cached rates without waiting for a network refresh.

The module owns its string catalog under `Resources`. Xcode generates typed accessors during the build; add translations there rather than editing generated Swift files.
