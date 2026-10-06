# Settings

Creator portrait and contact links, appearance preferences, language preferences through system Settings, rate information, and entry points to location setup and onboarding replay.

The creator footer appears below Feedback, before the version, with the original portrait, localized “Made by Dimasike” attribution, and interactive Liquid Glass capsule controls for email (`mailto:dimasike.dev@gmail.com`), website (`https://dimasike.com`), and X (`https://x.com/dimasike_`). The contacts share the Settings table’s outer horizontal insets; X includes its logo. The controls inherit the selected tint and adapt to a vertical arrangement from the extra-extra-large text size onward. A single portrait tap makes a full coin rotation, briefly exposing a random SF Symbols currency face before automatically returning to the portrait. Each next currency differs from the last. Reduce Motion uses a brief crossfade and also restores the portrait. The coin exposes its flip action and current face to accessibility. Feedback provides one row that opens a native Email/X choice alert, with a section footer inviting bug reports and ideas. Both Email entry points open an in-app mail composer when configured, otherwise the system mail handler, with a copy-address alert when unavailable. A native composer failure also offers the copyable address after dismissal. The app version remains at the bottom of Settings.

`Settings` owns flow state and behavior; `SettingsUI` owns presentation and resources. The host owns persisted preferences and cross-feature actions. Settings observes updates for the lifetime of its flow, including navigation to child pages.

## Harness

Select the `SettingsHarness` scheme and add launch arguments under **Run → Arguments**. Pass the argument directly, without `--case`.

| Case | Behavior |
| --- | --- |
| No arguments | Normal Settings flow. |
| `failure` | Refresh and replay actions fail when invoked. |
| `dated` | Fixed retrieved and checked timestamps for localization and layout checks. |
