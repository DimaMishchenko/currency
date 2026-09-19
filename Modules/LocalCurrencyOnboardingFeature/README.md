# LocalCurrencyOnboardingFeature

Owns the local-currency explanation, native foreground permission request, coarse result map, and permission/error recovery. `LocalCurrencyOnboardingScreen` is its public entry point. Its optional app mode enables a persistent Local selection after a successful lookup, so subsequent location updates change the converter currency. There is no manual fallback or Change/Clear menu; permission lives in system Settings, and Local can be removed from the app currency list.

The shared `CurrencySupport.LocalCurrencyController` owns permission reconciliation, one-shot lookup, and daily refresh. The app checks while active; authorized location widgets check during ordinary timeline refreshes. Widget scheduling and visibility are controlled by iOS, so a precise daily deadline is not guaranteed. Successful observations stay fresh for 24 hours; failed automatic attempts retry no more than hourly. Shared lookup generations prevent older results from overwriting newer results or restored permission failures.

The feature creates no map before a fresh authorized lookup succeeds. Only the country, currency, and observation time are saved; the broad map region remains in memory. Dismissal cancels pending work. Approximate accuracy is sufficient. The privacy explanation is a small caption beneath the bottom action.

`Resources/LocalCurrency.xcstrings` owns its text. The feature does not import ConverterFeature, CurrencySelectionUI, or WidgetOnboardingFeature. Location state-machine and real framework resource checks run in CurrencyIntegrationTests.
