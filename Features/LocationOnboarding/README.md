# LocationOnboarding

Local currency setup and permission-recovery presentation.

`LocationOnboarding` owns flow state and behavior; `LocationOnboardingUI` owns presentation and resources. The model receives location capabilities from the host. Permission prompts follow explicit user actions; presentation does not create a live location controller.

## Harness

Select the `LocationOnboardingHarness` scheme and add launch arguments under **Run → Arguments**. Pass one argument directly, without `--case`.

| Case | Behavior |
| --- | --- |
| No arguments | Initial location setup. |
| `ready` | Saved Czech location resolving to CZK. |
| `failure` | Permission-denied recovery state. |
