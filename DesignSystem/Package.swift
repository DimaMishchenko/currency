// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "DesignSystem", platforms: [.iOS("16.0")],
  products: [.library(name: "DesignSystem", targets: ["DesignSystem"])],
  targets: [
    .target(name: "DesignSystem"),
    .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])
  ])
