// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "WidgetOnboarding", defaultLocalization: "en", platforms: [.iOS("26.0")],
  products: [
    .library(name: "WidgetOnboarding", targets: ["WidgetOnboarding"]),
    .library(name: "WidgetOnboardingUI", targets: ["WidgetOnboardingUI"])
  ],
  dependencies: [
    .package(path: "../../Domain/Widgets"), .package(path: "../../Domain/Conversion"),
    .package(path: "../../Domain/ExchangeRates"), .package(path: "../../DesignSystem")
  ],
  targets: [
    .target(
      name: "WidgetOnboarding",
      dependencies: [
        .product(name: "Widgets", package: "Widgets"),
        .product(name: "Conversion", package: "Conversion"),
        .product(name: "ExchangeRates", package: "ExchangeRates")
      ]),
    .target(
      name: "WidgetOnboardingUI",
      dependencies: [
        "WidgetOnboarding", .product(name: "Widgets", package: "Widgets"),
        .product(name: "WidgetsUI", package: "Widgets"),
        .product(name: "Conversion", package: "Conversion"),
        .product(name: "CurrencySelectionUI", package: "Conversion"),
        .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "ExchangeRatesUI", package: "ExchangeRates"),
        .product(name: "DesignSystem", package: "DesignSystem")
      ], resources: [.process("Resources")]),
    .testTarget(
      name: "WidgetOnboardingTests",
      dependencies: [
        "WidgetOnboarding", "WidgetOnboardingUI", .product(name: "Widgets", package: "Widgets"),
        .product(name: "WidgetsUI", package: "Widgets"),
        .product(name: "Conversion", package: "Conversion"),
        .product(name: "ExchangeRates", package: "ExchangeRates")
      ])
  ])
