# Onboarding

Initial setup, currency selection, and resumable onboarding progress.

`Onboarding` owns flow state and behavior; `OnboardingUI` owns presentation and resources. Draft choices stay separate from confirmed converter input. Completion is saved before the flow finishes; the host supplies widget demonstrations.

## Harness

Select the `OnboardingHarness` scheme and add launch arguments under **Run → Arguments**. Use `--case <name>`; for example, `--case offline`. Omitting it selects `normal`.

| Case | Behavior |
| --- | --- |
| `normal` | Welcome with cached rates. |
| `selection` | Resume currency selection. |
| `finale` | Resume the final confirmation. |
| `offline` | No cached rates; bootstrap reports offline. |
| `save-failure` | Start at selection; the first progress save fails and retry can succeed. |
| `loading` | Delayed bootstrap without cached rates. |
| `interrupted` | The same delayed bootstrap, for background/resume checks. |
