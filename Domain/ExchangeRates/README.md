# ExchangeRates

Reusable current rates, conversion, offline snapshots, and historical series. `ExchangeRatesUI` adds currency presentation, artwork, and localized rate messages.

The core is independent of UI and app configuration. The app integrates this package through `Tuist/Package.swift`; core and UI tests run in the `CurrencyTests` scheme.

The [core usage guide](Sources/ExchangeRates/README.md) covers rate and history APIs.
