// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "LocalCurrency",
  platforms: [.macOS(.v14), .iOS("26.0")],
  products: [.library(name: "LocalCurrency", targets: ["LocalCurrency"])],
  dependencies: [
    .package(path: "../../Infrastructure/CoordinatedFiles"),
    .package(path: "../ExchangeRates")
  ],
  targets: [
    .target(
      name: "LocalCurrency",
      dependencies: [
        .product(name: "ExchangeRates", package: "ExchangeRates"),
        .product(name: "CoordinatedFiles", package: "CoordinatedFiles")
      ]),
    .testTarget(name: "LocalCurrencyTests", dependencies: ["LocalCurrency"])
  ]
)
