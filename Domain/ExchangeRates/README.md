# ExchangeRates

Reusable current rates, conversion, offline snapshots, and historical series. `ExchangeRatesUI` adds currency presentation, artwork, and localized rate messages.

The core is independent of UI and app configuration. The app integrates this package through `Tuist/Package.swift`; core and UI tests run in the `CurrencyTests` scheme.

The [core usage guide](Sources/ExchangeRates/README.md) covers rate and history APIs.

Current crypto reference prices and intraday history use Coin Metrics Community; daily Fawaz fallback and selected Frankfurter fiat sources support reference conversions and longer history. Bundled monthly history extends coverage where observations exist. [Data sources and licences](../../Documentation/DataSources.md) describe attribution, sampling and reuse conditions.
