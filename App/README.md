# Currency app

The executable composition root. It creates the history service and connects `ConverterScreen` to `RateDetailsScreen`. Feature behavior belongs to the feature targets; App Group provisioning and the URL scheme belong to the app and widget executables.

Run `tuist generate --no-open`, open `Currency.xcworkspace`, and run the `Currency` scheme on an iOS 26 simulator. Device builds need an Apple signing team and the registered App Group.

The `CurrencyIntegrationTests` scheme validates localized resource lookup and fallback across feature frameworks.
