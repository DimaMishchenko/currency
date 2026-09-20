// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Conversion", defaultLocalization: "en",
  platforms: [.macOS(.v14), .iOS("26.0")],
  products: [
    .library(name: "Conversion", targets: ["Conversion"]),
    .library(name: "CurrencySelectionUI", targets: ["CurrencySelectionUI"])
  ],
  dependencies: [
    .package(path: "../../DesignSystem"),
    .package(path: "../ExchangeRates"),
    .package(path: "../LocalCurrency")
  ],
  targets: [
    .target(
      name: "CurrencySelectionUI",
      dependencies: [
        "Conversion", .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "ExchangeRatesUI", package: "ExchangeRates"),
        .product(name: "DesignSystem", package: "DesignSystem")
      ], resources: [.process("Resources")]),
    .target(
      name: "Conversion",
      dependencies: [
        .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "LocalCurrency", package: "LocalCurrency")
      ]),
    .testTarget(
      name: "ConversionTests",
      dependencies: [
        "Conversion", .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "LocalCurrency", package: "LocalCurrency")
      ])
  ]
)
