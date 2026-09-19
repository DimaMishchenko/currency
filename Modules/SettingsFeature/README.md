# SettingsFeature

Owns Settings navigation, theme and accent selection, the system Location settings link, rate freshness and quote information, sources, acknowledgements, and onboarding replay.

`SettingsScreen` accepts a `RateSnapshot`, ordered currency codes, refresh status, an optional localized warning, an async refresh action, a host-owned location-management action, and an optional throwing onboarding replay action. The host supplies updated values as rate state changes. It renders inside a host-owned NavigationStack and consumes `AppAppearance` from the environment.

The feature depends only on CurrencySupport and ExchangeRates. It does not import ConverterFeature or own a second rate service. CurrencyApp composes the screen through ConverterScreen's generic settings destination. Refresh continues to use the converter's existing service and storage; onboarding replay calls OnboardingFlow directly through the app.

AppAppearance remains in CurrencySupport and persists app-local preferences. The app root applies the selected theme and accent across features; widgets retain system appearance. The host routes Location to setup when authorization is not determined and otherwise opens the public `UIApplication.openSettingsURLString` destination. Permission reconciliation remains owned by the app and local-currency feature.

The English string catalog belongs to this module. Settings-only strings were removed from Converter.xcstrings; shared labels such as Settings and Close have entries in each owning catalog. Resource integration tests validate the Settings bundle and language fallback.

Settings uses a large navigation title and native theme and accent menus directly in the root list. Source and artwork credit titles use primary text color while external-link affordances retain tint. Replay onboarding uses a setup-card icon without a footer. Rates use compact, leading-aligned currency/provider/timestamp rows; Published, Retrieved, and Last trade preserve the meaning of each timestamp.

The accent selector spaces its color dot and name explicitly. Its native menu keeps the platform selection checkmark on the left and preserves each swatch color.

The final section contains a non-interactive Send feedback / Coming soon placeholder until a support destination is configured. Its footer displays the host app version and build from Bundle.main metadata.
