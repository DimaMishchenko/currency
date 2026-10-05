// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "CurrencyDetails",
  defaultLocalization: "en",
  platforms: [.iOS("26.0"), .watchOS("26.0")],
  products: [
    .library(name: "CurrencyDetailsWatchUI", targets: ["CurrencyDetailsWatchUI"]),
    .library(name: "CurrencyDetails", targets: ["CurrencyDetails"]),
    .library(name: "CurrencyDetailsUI", targets: ["CurrencyDetailsUI"])
  ],
  dependencies: [
    .package(path: "../../Domain/ExchangeRates"), .package(path: "../../Foundation/DesignSystem")
  ],
  targets: [
    .target(
      name: "CurrencyDetailsWatchUI",
      dependencies: [
        "CurrencyDetails", .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "ExchangeRatesUI", package: "ExchangeRates")
      ],
      resources: [.process("Resources")]),
    .target(
      name: "CurrencyDetails",
      dependencies: [.product(name: "ExchangeRates", package: "ExchangeRates")]),
    .target(
      name: "CurrencyDetailsUI",
      dependencies: [
        "CurrencyDetails", .product(name: "ExchangeRatesUI", package: "ExchangeRates"),
        .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "ExchangeRates", package: "ExchangeRates")
      ], resources: [.process("Resources")]),
    .testTarget(
      name: "CurrencyDetailsTests",
      dependencies: ["CurrencyDetails", .product(name: "ExchangeRates", package: "ExchangeRates")])
  ]
)
