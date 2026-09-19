# Currency

A SwiftUI currency converter for iOS 26, with a personal currency list, offline rates, and interactive Home and Lock Screen widgets.

## Run

With Xcode 26 or later and Tuist installed:

```sh
tuist generate --no-open
open Currency.xcworkspace
```

Select the `Currency` scheme and an iOS 26+ simulator. For device signing and validation, see [Development](Documentation/Development.md).

The reusable [ExchangeRates package](Sources/ExchangeRates/README.md) can also be consumed independently.

## Project guide

- [Project.swift](Project.swift) defines modules and dependencies; public API comments describe integration contracts.
- [Decisions](Documentation/Decisions.md): rationale, boundaries, and platform limits.
- [Development](Documentation/Development.md): essential commands and pitfalls.
- [To-do](Documentation/TODO.md): unfinished features and release checks.
- [Third-party assets](Documentation/ThirdPartyAssets.md): provenance and licenses.
