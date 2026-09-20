# CurrencyDetails

Current rate details and historical series for a selected currency pair.

`CurrencyDetails` owns flow state and behavior; `CurrencyDetailsUI` owns presentation and resources. The model owns range selection, loading, and recovery. The host supplies history access and the UI renders the resulting state.

## Harness

Select the `CurrencyDetailsHarness` scheme and add launch arguments under **Run → Arguments**. Use `--case <name>`; for example, `--case cached`. Omitting it selects `normal`.

| Case | Behavior |
| --- | --- |
| `normal` | Available history; changing the range changes the series. |
| `empty` | Unsupported pair with no series. |
| `failure` | History unavailable. |
| `cached` | History with a cached-series warning. |
| `loading` | Delayed history request. |
| `interrupted` | The same delay, for range-switching and cancellation checks. |
