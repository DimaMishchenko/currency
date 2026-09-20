// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Home",
  defaultLocalization: "en", platforms: [.iOS(.v26)],
  products: [
    .library(name: "Home", targets: ["Home"]), .library(name: "HomeUI", targets: ["HomeUI"])
  ],
  dependencies: [
    .package(path: "../../Domain/Conversion"), .package(path: "../../Domain/LocalCurrency"),
    .package(path: "../../Domain/ExchangeRates"), .package(path: "../../DesignSystem")
  ],
  targets: [
    .target(
      name: "Home",
      dependencies: [
        .product(name: "Conversion", package: "Conversion"),
        .product(name: "LocalCurrency", package: "LocalCurrency"),
        .product(name: "ExchangeRates", package: "ExchangeRates")
      ]),
    .target(
      name: "HomeUI",
      dependencies: [
        "Home", .product(name: "Conversion", package: "Conversion"),
        .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "CurrencySelectionUI", package: "Conversion"),
        .product(name: "ExchangeRatesUI", package: "ExchangeRates"),
        .product(name: "DesignSystem", package: "DesignSystem")
      ], resources: [.process("Resources")]),
    .testTarget(
      name: "HomeTests",
      dependencies: [
        "Home", .product(name: "Conversion", package: "Conversion"),
        .product(name: "LocalCurrency", package: "LocalCurrency"),
        .product(name: "ExchangeRates", package: "ExchangeRates")
      ]),
    .testTarget(name: "HomeUITests", dependencies: ["HomeUI"])
  ]
)
