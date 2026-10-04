# Home

The main converter: amount editing, selected currencies, and rate-refresh feedback.

`Home` owns flow state and behavior; `HomeUI` owns presentation and resources. The logic model receives storage and refresh capabilities. The UI emits navigation requests; the app opens their destinations.

Converter discovery uses native TipKit popovers. After one completed amount edit, the next editing interaction can introduce rate history from the keypad button if details have not been opened. The widget tip waits until a later calendar day and a new completed edit with usable converted results, then appears when the keypad closes and the converter is idle. It is excluded from the onboarding completion visit, suppressed after opening the widget guide, and never follows a shown history tip in the same foreground visit. The app supplies onboarding status, clock, and app-local discovery persistence through `HomeDependencies`; TipKit owns native presentation and dismissal.

`HomeWatchUI` presents the same `HomeModel` with a full-screen decimal keypad using shared converter editing rules, presets, a searchable currency picker, selected destinations, refresh feedback, and semantic details requests. Swipe a destination to remove it or promote its converted value to the base. The Watch executable owns navigation, shared-state observation dependencies, and rate refresh scheduling.

The Watch converter places its compact amount and source controls immediately before the first result, with presets below that result. Currency pickers show the current source and favorites before the remaining catalog; search still covers every eligible currency. The amount editor keeps native dismissal and confirmation controls and allocates its remaining height to all four keypad rows.

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
| `discovery-history` | Open the keypad to inspect the native history tip. |
| `discovery-widgets` | Change an amount and close the keypad to inspect the native widgets tip. |
