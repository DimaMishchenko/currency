# Onboarding

Initial setup, currency selection, and resumable onboarding progress.

`Onboarding` owns flow state and behavior; `OnboardingUI` owns presentation and resources. Draft choices stay separate from confirmed converter input. Completion is saved before the flow finishes; the host supplies widget demonstrations. The model reads confirmed input to preserve existing choices and applies USD/EUR only to untouched first-launch defaults. It owns rate coverage and the one-day retry threshold using the supplied clock. Replay commits current choices through `OnboardingProgressStore.restart(input:)`, then the application starts a new flow identity.

## Harness

Select the `OnboardingHarness` scheme and add launch arguments under **Run → Arguments**. Use `--case <name>`; for example, `--case offline`. Omitting it selects `normal`.

The harness declares the app's supported languages. Add `-AppleLanguages (de) -AppleLocale de_DE` to check German copy, or substitute another supported language and region.

| Case | Behavior |
| --- | --- |
| `normal` | Welcome with cached rates. |
| `selection` | Resume currency selection. |
| `finale` | Resume the final confirmation. |
| `offline` | No cached rates; bootstrap reports offline. |
| `save-failure` | Start at selection; the first progress save fails and retry can succeed. |
| `loading` | Delayed bootstrap without cached rates. |
| `interrupted` | The same delayed bootstrap, for background/resume checks. |
