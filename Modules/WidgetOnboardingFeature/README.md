# WidgetOnboardingFeature

Owns widget discovery, the moving showcase, isolated interactive previews, and step-by-step Home Screen and Lock Screen tutorials. `WidgetOnboardingScreen` is its public entry point. The host supplies a local-currency destination so this feature does not import another feature.

The feature renders real layouts from `WidgetPresentation` and replaces AppIntent dispatch with temporary in-memory actions. Sample rates are labeled. Preview actions do not write app input, configured widget state, or location. `CurrencySelectionUI` supplies the reusable picker for tutorial settings.

`Resources/WidgetOnboarding.xcstrings` owns the feature's text. Generated accessors resolve this framework's bundle. The app integration target validates resource lookup, substitutions, and preview state behavior.
