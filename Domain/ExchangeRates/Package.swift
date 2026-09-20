// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ExchangeRates", defaultLocalization: "en", platforms: [.macOS(.v14), .iOS("16.0")],
  products: [
    .library(name: "ExchangeRates", targets: ["ExchangeRates"]),
    .library(name: "ExchangeRatesDynamic", type: .dynamic, targets: ["ExchangeRates"]),
    .library(name: "ExchangeRatesUI", targets: ["ExchangeRatesUI"])
  ], dependencies: [.package(path: "../../DesignSystem")],
  targets: [
    .target(name: "ExchangeRates", exclude: ["README.md"]),
    .target(
      name: "ExchangeRatesUI",
      dependencies: ["ExchangeRates", .product(name: "DesignSystem", package: "DesignSystem")],
      resources: [.process("Resources")]),
    .testTarget(name: "ExchangeRatesTests", dependencies: ["ExchangeRates"]),
    .testTarget(name: "ExchangeRatesUITests", dependencies: ["ExchangeRatesUI", "ExchangeRates"])
  ])
