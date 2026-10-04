# CurrencyDetails

Current rate details and historical series for a selected currency pair.

`CurrencyDetails` owns flow state and behavior; `CurrencyDetailsUI` owns presentation and resources. The model owns range selection, loading, and recovery. The host supplies history access and the UI renders the resulting state.

`CurrencyDetailsWatchUI` presents the same `CurrencyDetailsModel` with native range selection, Swift Charts, cached-history issues, and rate provenance. `CurrencyDetailsWatchScreen` receives immutable input and explicit history access; its view task owns cancellation and the model rejects stale range results. Explicit Watch widget links retain their requested pair, including inverted fiat/crypto history, while ordinary details retain the standard fiat reference policy.

## Harness

Select the `CurrencyDetailsHarness` scheme and add launch arguments under **Run → Arguments**. Use `--case <name>`; for example, `--case cached`. Omitting it selects `normal`.

| Case | Behavior |
| --- | --- |
| `normal` | Available history; changing the range changes the series. |
| `crypto` | BTC/USD history, including hourly observations for 1D. |
| `empty` | Unsupported pair with no series. |
| `failure` | History unavailable. |
| `cached` | History with a cached-series warning. |
| `loading` | Delayed history request. |
| `interrupted` | The same delay, for range-switching and cancellation checks. |
