// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Onboarding",
  defaultLocalization: "en",
  platforms: [.iOS("26.0")],
  products: [
    .library(name: "Onboarding", targets: ["Onboarding"]),
    .library(name: "OnboardingUI", targets: ["OnboardingUI"])
  ],
  dependencies: [
    .package(path: "../../Domain/ExchangeRates"), .package(path: "../../DesignSystem"),
    .package(path: "../../Domain/Conversion")
  ],
  targets: [
    .target(
      name: "Onboarding",
      dependencies: [
        .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "Conversion", package: "Conversion")
      ]),
    .target(
      name: "OnboardingUI",
      dependencies: [
        "Onboarding", .product(name: "ExchangeRatesUI", package: "ExchangeRates"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "Conversion", package: "Conversion"),
        .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "CurrencySelectionUI", package: "Conversion")
      ], resources: [.process("Resources")]),
    .testTarget(
      name: "OnboardingTests",
      dependencies: [
        "Onboarding", .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "Conversion", package: "Conversion")
      ])
  ]
)
