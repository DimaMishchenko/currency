# LocalCurrencyOnboardingFeature

Owns the on-demand local-currency explanation, native foreground permission request, one-shot lookup, coarse result map, and manual/error recovery. `LocalCurrencyOnboardingScreen` is its public entry point; `LocalCurrencyAuthorization.reconcile()` handles foreground permission changes without requesting a location.

The feature creates no map before a fresh authorized lookup succeeds. It saves only the country, currency, and observation time in `CurrencyStore`; the broad map region remains in memory. Dismissal cancels pending work and late callbacks cannot save results. Approximate accuracy is sufficient; the app declares that default in its Info.plist.

`Resources/LocalCurrency.xcstrings` owns its text. `CurrencySelectionUI` supplies manual selection. The feature does not import ConverterFeature or WidgetOnboardingFeature. Location state-machine and real framework resource checks run in CurrencyIntegrationTests.
