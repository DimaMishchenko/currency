// swift-tools-version: 6.2
import PackageDescription

#if TUIST
  import ProjectDescription

  let packageSettings = PackageSettings(
    baseSettings: .settings(base: [
      "SWIFT_VERSION": "6.0",
      "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
      "SWIFT_EMIT_LOC_STRINGS": "YES",
      "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES"
    ])
  )
#endif

let package = Package(
  name: "CurrencyDependencies",
  dependencies: [
    .package(path: "../Infrastructure/CoordinatedFiles"),
    .package(path: "../DesignSystem"),
    .package(path: "../Domain/ExchangeRates"),
    .package(path: "../Domain/LocalCurrency"),
    .package(path: "../Domain/Conversion"),
    .package(path: "../Domain/Widgets"),
    .package(path: "../Features/Home"),
    .package(path: "../Features/Onboarding"),
    .package(path: "../Features/CurrencyDetails"),
    .package(path: "../Features/Settings"),
    .package(path: "../Features/LocationOnboarding"),
    .package(path: "../Features/WidgetOnboarding")
  ]
)
