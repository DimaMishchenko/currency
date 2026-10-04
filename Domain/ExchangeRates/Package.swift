// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ExchangeRates", defaultLocalization: "en",
  platforms: [.macOS(.v14), .iOS("26.0"), .watchOS("26.0")],
  products: [
    .library(name: "ExchangeRates", targets: ["ExchangeRates"]),
    .library(name: "ExchangeRatesUI", targets: ["ExchangeRatesUI"])
  ],
  dependencies: [
    .package(path: "../../Foundation/CoordinatedFiles")
  ],
  targets: [
    .target(
      name: "ExchangeRates",
      dependencies: [.product(name: "CoordinatedFiles", package: "CoordinatedFiles")],
      exclude: ["README.md"]),
    .target(
      name: "ExchangeRatesUI",
      dependencies: ["ExchangeRates"],
      resources: [.process("Resources")]),
    .testTarget(name: "ExchangeRatesTests", dependencies: ["ExchangeRates"]),
    .testTarget(name: "ExchangeRatesUITests", dependencies: ["ExchangeRatesUI", "ExchangeRates"])
  ])
