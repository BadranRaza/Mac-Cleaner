// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "MacCleaner",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(
      name: "MacCleanerCore",
      targets: ["MacCleanerCore"]
    ),
    .executable(
      name: "mac-cleaner",
      targets: ["mac-cleaner"]
    ),
    .executable(
      name: "unity-detector",
      targets: ["unity-detector"]
    ),
    .executable(
      name: "MacCleanerGUI",
      targets: ["MacCleanerGUI"]
    )
  ],
  targets: [
    .target(
      name: "MacCleanerCore",
      path: "Sources/UnityProjectDetectorCore"
    ),
    .executableTarget(
      name: "mac-cleaner",
      dependencies: ["MacCleanerCore"],
      path: "Sources/mac-cleaner"
    ),
    .executableTarget(
      name: "unity-detector",
      dependencies: ["MacCleanerCore"],
      path: "Sources/unity-detector"
    ),
    .executableTarget(
      name: "MacCleanerGUI",
      dependencies: ["MacCleanerCore"],
      path: "Sources/MacCleanerGUI",
      exclude: ["MacCleanerGUI.entitlements"]
    ),
    .testTarget(
      name: "MacCleanerCoreTests",
      dependencies: ["MacCleanerCore"],
      path: "Tests/MacCleanerCoreTests"
    )
  ]
)
