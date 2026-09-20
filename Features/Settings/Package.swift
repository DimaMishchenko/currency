// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Settings", defaultLocalization: "en", platforms: [.iOS("26.0")],
  products: [
    .library(name: "Settings", targets: ["Settings"]),
    .library(name: "SettingsUI", targets: ["SettingsUI"])
  ],
  dependencies: [
    .package(path: "../../Domain/ExchangeRates"), .package(path: "../../DesignSystem")
  ],
  targets: [
    .target(
      name: "Settings", dependencies: [.product(name: "ExchangeRates", package: "ExchangeRates")]),
    .target(
      name: "SettingsUI",
      dependencies: [
        "Settings", .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "ExchangeRatesUI", package: "ExchangeRates"),
        .product(name: "DesignSystem", package: "DesignSystem")
      ], resources: [.process("Resources")]),
    .testTarget(
      name: "SettingsTests",
      dependencies: ["Settings", .product(name: "ExchangeRates", package: "ExchangeRates")])
  ])
