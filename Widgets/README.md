# CurrencyWidgets

The WidgetKit extension provides the converter, currency board, and quick-rate Lock Screen widgets. It follows the amount and ordered currencies saved by the app. The large converter includes an App Intent keypad.

Build and run the `Currency` app, then add a Currency widget from the Home Screen or Lock Screen gallery. App and extension must share the configured App Group. Keep simulator signing enabled when testing storage integration.

This executable exposes no library API. It consumes `CurrencySupport` and `ExchangeRates`; iOS controls timeline scheduling and interactive update timing.

The module owns its English string catalog under `Resources`. Xcode generates typed accessors during the build; add translations there rather than editing generated Swift files.
