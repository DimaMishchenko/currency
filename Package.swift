// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "RateCore",
  platforms: [
    .macOS(.v14),
    .iOS(.v26)
  ],
  products: [
    .library(name: "RateCore", targets: ["RateCore"])
  ],
  targets: [
    .target(name: "RateCore"),
    .testTarget(name: "RateCoreTests", dependencies: ["RateCore"])
  ]
)
