// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ExchangeRates",
  platforms: [
    .macOS(.v14),
    .iOS(.v16)
  ],
  products: [
    .library(name: "ExchangeRates", targets: ["ExchangeRates"]),
    .library(name: "ExchangeRatesDynamic", type: .dynamic, targets: ["ExchangeRates"])
  ],
  targets: [
    .target(name: "ExchangeRates", exclude: ["README.md"]),
    .testTarget(name: "ExchangeRatesTests", dependencies: ["ExchangeRates"])
  ]
)
