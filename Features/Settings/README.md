# Settings

Appearance preferences, rate information, and entry points to location setup and onboarding replay.

`Settings` owns flow state and behavior; `SettingsUI` owns presentation and resources. The host owns persisted preferences and cross-feature actions. Settings observes updates for the lifetime of its flow, including navigation to child pages.

## Harness

Select the `SettingsHarness` scheme and add launch arguments under **Run → Arguments**. Pass the argument directly, without `--case`.

| Case | Behavior |
| --- | --- |
| No arguments | Normal Settings flow. |
| `failure` | Refresh and replay actions fail when invoked. |
