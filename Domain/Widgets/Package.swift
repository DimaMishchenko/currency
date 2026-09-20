// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Widgets", defaultLocalization: "en",
  platforms: [.macOS(.v14), .iOS("26.0")],
  products: [
    .library(name: "Widgets", targets: ["Widgets"]),
    .library(name: "WidgetsUI", targets: ["WidgetsUI"])
  ],
  dependencies: [
    .package(path: "../../DesignSystem"),
    .package(path: "../ExchangeRates"),
    .package(path: "../LocalCurrency"),
    .package(path: "../Conversion")
  ],
  targets: [
    .target(
      name: "WidgetsUI",
      dependencies: [
        "Widgets", .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "ExchangeRatesUI", package: "ExchangeRates"),
        .product(name: "LocalCurrency", package: "LocalCurrency"),
        .product(name: "Conversion", package: "Conversion"),
        .product(name: "DesignSystem", package: "DesignSystem")
      ], resources: [.process("Resources")]),
    .target(
      name: "Widgets",
      dependencies: [
        .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "LocalCurrency", package: "LocalCurrency"),
        .product(name: "Conversion", package: "Conversion")
      ]),
    .testTarget(
      name: "WidgetsTests",
      dependencies: [
        "Widgets", .product(name: "Conversion", package: "Conversion"),
        .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "LocalCurrency", package: "LocalCurrency")
      ])
  ]
)
