# Home

The main converter: amount editing, selected currencies, and rate-refresh feedback.

`Home` owns flow state and behavior; `HomeUI` owns presentation and resources. The logic model receives storage and refresh capabilities. The UI emits navigation requests; the app opens their destinations.

## Harness

Select the `HomeHarness` scheme and add launch arguments under **Run → Arguments**. Use `--case <name>`; for example, `--case save-failure`. Omitting it selects `normal`.

| Case | Behavior |
| --- | --- |
| `normal` | Editable currencies with available rates. |
| `empty` | No destination currencies. |
| `unavailable` | No available rates. |
| `local-stale` | Local currency with an old saved observation. |
| `save-failure` | The first input edit fails; the next edit can succeed. |
| `refresh-failure` | Pull to refresh to trigger a storage failure. |
| `refresh-warning` | Pull to refresh to show a provider warning. |
| `loading` | Pull to refresh to start a delayed request. |
| `interrupted` | The same delayed refresh, for background/cancellation checks. |
