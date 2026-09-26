// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "CoordinatedFiles", platforms: [.macOS(.v14), .iOS(.v16)],
  products: [.library(name: "CoordinatedFiles", targets: ["CoordinatedFiles"])],
  targets: [.target(name: "CoordinatedFiles")]
)
