# OnboardingFeature

Owns first-launch setup, rate bootstrap and recovery, ordered draft selection, resumability, and completion. `OnboardingFlow` is the public entry point. Its model, screen, supporting views, and timing/storage test seams are internal.

The host supplies Home Screen and widget showcase scenes through `OnboardingWidgetScene`, plus the converter destination. The destination receives a throwing replay callback that saves new progress before returning to setup. No feature imports another feature implementation.

`CurrencySupport` owns the independent `OnboardingProgress` record and coordinated storage; `ExchangeRates` supplies progressive provider results. Preview amounts never replace the app's saved amount. Only successful selection confirmation updates app currency choices, and successful completion reveals the converter.

The feature owns `Resources/Onboarding.xcstrings` and uses Xcode-generated accessors. Generate the workspace with `tuist generate --no-open`; model regression tests run in the `CurrencyIntegrationTests` scheme through `@testable import OnboardingFeature`.
