# Currency

[![Tests](https://github.com/DimaMishchenko/currency/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/DimaMishchenko/currency/actions/workflows/tests.yml)
[![TestFlight Publish](https://github.com/DimaMishchenko/currency/actions/workflows/publish.yml/badge.svg?branch=main)](https://github.com/DimaMishchenko/currency/actions/workflows/publish.yml)
[![Public Beta](https://github.com/DimaMishchenko/currency/actions/workflows/public-beta.yml/badge.svg?branch=main)](https://github.com/DimaMishchenko/currency/actions/workflows/public-beta.yml)

A SwiftUI currency converter for iOS 26, with a personal currency list, offline rates, and interactive Home and Lock Screen widgets.

## Run

With Xcode 26 or later and the Tuist version from `.mise.toml` installed:

```sh
mise install
mise exec -- tuist install
mise exec -- tuist generate
```

Select the `Currency` scheme and an iOS 26+ simulator. For device signing and validation, see [Development](Documentation/Development.md).

Tuist automatically uses cached dependencies when available. No account is required to build; see [Development](Documentation/Development.md#dependency-cache) for optional cache warming and source-only generation.

## Source layout

- [App](App/README.md) contains executable composition, scene UI, application modules, integration tests, and the widget extension under `App/Widgets/`.
- `Features/` contains the Home, Onboarding, CurrencyDetails, Settings, LocationOnboarding, and WidgetOnboarding packages. Each separates logic from UI and has an isolated harness app.
- `Domain/` contains ExchangeRates, Conversion, LocalCurrency, and Widgets packages. Reusable currency and widget UI lives beside its domain logic.
- [DesignSystem](DesignSystem/README.md) contains general presentation primitives. UI targets own their resources.

Build the `CurrencyHarnesses` scheme for all seven harness apps, and run `CurrencyTests` for the combined package, application, and widget test suite. Each package and application module has a short README; modules with harnesses list their launch arguments there. See [Development](Documentation/Development.md) for the shared workflow.

## Project guide

- [Architecture](Documentation/Architecture.md): enduring architecture principles, dependency injection, state, and flow ownership.
- [Project.swift](Project.swift) defines modules and dependencies; public API comments describe integration contracts.
- [Decisions](Documentation/Decisions.md): rationale, boundaries, and platform limits.
- [Development](Documentation/Development.md): essential commands and pitfalls.
- [Issues](https://github.com/DimaMishchenko/currency/issues): unfinished features, maintenance, and release checks.
- [Third-party assets](Documentation/ThirdPartyAssets.md): provenance and licenses.
