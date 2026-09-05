# Localization

The app currently ships English source strings only. Each feature owns an Xcode string catalog: `Converter.xcstrings`, `Details.xcstrings`, and `Support.xcstrings`; the extension owns `Widgets.xcstrings`. App and extension display names live in `InfoPlist.xcstrings`. Add translations to these catalogs when another language is approved.

`STRING_CATALOG_GENERATE_SYMBOLS` and `SWIFT_EMIT_LOC_STRINGS` are enabled in the Tuist project. Xcode generates internal `LocalizedStringResource` accessors at build time; generated Swift files are not checked in. Within the owning module, use them directly:

```swift
Text(.Details.historyHeading)
Text(.Details.unitConversion(code, quote))
```

Keep keys semantic and manually managed in the catalog. Placeholder arguments belong to a single catalog entry so translators can reorder them. Warnings return localized resources and resolve in SwiftUI. Currency names, amounts, editable digits, publication dates, and chart labels respect the view locale; currency codes and provider/asset proper names remain data.

Rate provenance arrives as typed provider and observation metadata. `RateMessages` selects localized templates from those enums; custom provider names pass through as data. No display-string matching is required.

App Intents is the compiler-enforced exception: its metadata extractor requires literal `LocalizedStringResource` initializers for intent titles and parameters. Those two declarations reference entries in the same widget catalog. Ordinary widget views and configuration use generated accessors.

## Resource ownership

The three app modules are dynamic frameworks so Xcode-generated accessors resolve their owning resource bundle using `Bundle(for:)`. No custom localization getter generator or bundle-rewriting wrapper is used. The app consumes the root package's `ExchangeRatesDynamic` product, embedded explicitly; other repositories can continue using the automatic-linking `ExchangeRates` product. Both products expose the same module and source API. Do not link both products into one executable.

Tuist's native-package graph checker conservatively reports this package as static even though its manifest explicitly declares the dynamic product. Verify actual embedding/linkage when changing this setup; the compiled frameworks must reference the shared rate framework, which must be present in the host's Frameworks directory.

## Validation

Generate with `tuist generate --no-open`. Run the `CurrencyIntegrationTests` scheme on an iOS 26 simulator to exercise real framework resource lookup, positional substitutions, and English fallback. The `CurrencySupport` scheme covers locale formatting and converter behavior. Export translations through Xcode's Product → Export Localizations command; translated catalogs remain the source of truth.

See Apple's [generated localizable symbols documentation](https://developer.apple.com/documentation/xcode/using-generated-localizable-symbols-in-your-code) for the accessor workflow.
