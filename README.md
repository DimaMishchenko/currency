# Currency

A SwiftUI currency converter for iOS 26, with a personal currency list, offline rates, and interactive Home and Lock Screen widgets.

## Run

With Xcode 26 or later and Tuist installed:

```sh
tuist generate --no-open
open Currency.xcworkspace
```

Select the `Currency` scheme and an iOS 26+ simulator. For device signing and validation, see [Development](Documentation/Development.md).

The reusable [ExchangeRates package](Domain/ExchangeRates/README.md) can also be consumed independently on iOS 16+ and macOS 14+. The root `Package.swift` preserves repository-URL consumers; the app uses the nested `Domain/ExchangeRates` package. Choose one core product per executable.

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
- [TestFlight](Documentation/TestFlight.md): GitHub Actions release setup and signing renewal.
- [To-do](Documentation/TODO.md): unfinished features and release checks.
- [Third-party assets](Documentation/ThirdPartyAssets.md): provenance and licenses.
