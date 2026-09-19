# Development

## Build and validate

Run commands from the repository root. Use Xcode with Swift 6.2+ and an iOS 26+ simulator, Tuist, and `xcbeautify`.

Regenerate with `tuist generate --no-open` after manifest or dependency-graph changes. Source changes inside buildable folders do not require regeneration. The manifests and generated schemes are the source of truth for targets.

```sh
swift test
swift format lint --recursive --strict Sources Tests Modules App/Sources App/Tests Widgets/Sources
```

In Xcode, build `Currency` and run `CurrencySupport` and `CurrencyIntegrationTests`. For command-line runs, choose an installed simulator UUID:

```sh
SIMULATOR_ID='<simulator UUID>'
set -o pipefail
xcodebuild test -workspace Currency.xcworkspace -scheme CurrencyIntegrationTests \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  CODE_SIGN_IDENTITY=- 2>&1 | xcbeautify
```

Use the same destination/signing options with the `CurrencySupport` scheme for support tests, or `build -scheme Currency -configuration Debug` / `Release` for app and widget builds. Xcode's Build Documentation checks the package API reference. Native release checks live in [TODO](TODO.md); passing model tests does not close them.

## Signing and resource pitfalls

- Device builds need a signing team for the app and extension and the registered `group.com.dimasike.currency` App Group. If changing identifiers, update the manifest, both entitlements, and the shared store consistently.
- Keep signing enabled for simulator integration tests. `CODE_SIGNING_ALLOWED=NO` can compile but removes entitlements needed by shared storage. Inspect the built bundle identifier before installing or changing simulator permissions; Debug and Release installations can coexist.
- Feature frameworks own their string catalogs, including Settings. Use Xcode-generated accessors in the owning module; keep placeholders in a single translatable entry. App Intent metadata requires literal localized-resource initializers. Export translations through Xcode; never edit generated Swift.
- Dynamic frameworks allow generated localization accessors to find their resource bundles. The app embeds `ExchangeRatesDynamic`; other consumers may use `ExchangeRates`. Never link both products into one executable. If changing linkage, verify actual embedding and resource lookup, not just Tuist's graph diagnostics.
- Feature hosts and previews must supply `AppAppearance` in the environment. Use isolated stores for tests and previews.
