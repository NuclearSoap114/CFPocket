// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TrainingCore", platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "TrainingCore", targets: ["TrainingCore"]),
    .library(name: "PocketCore", targets: ["PocketCore"]),
    .executable(name: "TrainingBench", targets: ["TrainingBench"]),
  ], dependencies: [.package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.3"), .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")],
  targets: [
    .target(name: "TrainingCore", dependencies: ["SwiftSoup"]),
    .target(name: "PocketCore", dependencies: ["TrainingCore", "SwiftSoup", .product(name: "Markdown", package: "swift-markdown")]),
    .testTarget(name: "PocketCoreTests", dependencies: ["PocketCore"]),
    .executableTarget(name: "TrainingBench", dependencies: ["TrainingCore"]),
    .testTarget(
      name: "TrainingCoreTests", dependencies: ["TrainingCore"], resources: [.copy("Fixtures")]),
  ], swiftLanguageModes: [.v5])
