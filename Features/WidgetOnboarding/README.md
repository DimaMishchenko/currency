# WidgetOnboarding

Widget discovery, installation guidance, and interactive demonstrations.

`WidgetOnboarding` owns flow state and behavior; `WidgetOnboardingUI` owns presentation and resources. Demonstrations use production layouts with isolated preview state. The host supplies action handlers and location presentation; previews do not change installed widgets.

## Harness

Select the `WidgetOnboardingHarness` scheme and add launch arguments under **Run → Arguments**. Pass one argument directly, without `--case`.

| Case | Behavior |
| --- | --- |
| No arguments | Full widget onboarding entry. |
| `home` | Onboarding Home Screen demonstration. |
| `showcase` | Interactive widget showcase. |
