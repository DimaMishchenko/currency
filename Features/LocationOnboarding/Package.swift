// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "LocationOnboarding", defaultLocalization: "en", platforms: [.iOS("26.0")],
  products: [
    .library(name: "LocationOnboarding", targets: ["LocationOnboarding"]),
    .library(name: "LocationOnboardingUI", targets: ["LocationOnboardingUI"])
  ],
  dependencies: [
    .package(path: "../../Domain/LocalCurrency"), .package(path: "../../Domain/Conversion"),
    .package(path: "../../Domain/ExchangeRates"), .package(path: "../../DesignSystem")
  ],
  targets: [
    .target(
      name: "LocationOnboarding",
      dependencies: [
        .product(name: "LocalCurrency", package: "LocalCurrency"),
        .product(name: "Conversion", package: "Conversion")
      ]),
    .target(
      name: "LocationOnboardingUI",
      dependencies: [
        "LocationOnboarding", .product(name: "ExchangeRatesUI", package: "ExchangeRates"),
        .product(name: "DesignSystem", package: "DesignSystem")
      ], resources: [.process("Resources")]),
    .testTarget(
      name: "LocationOnboardingTests",
      dependencies: [
        "LocationOnboarding", .product(name: "LocalCurrency", package: "LocalCurrency")
      ])
  ])
