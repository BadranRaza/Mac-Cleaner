// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "Reclaim",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Reclaim", targets: ["Reclaim"]),
    .executable(name: "reclaim-cli", targets: ["reclaim-cli"]),
  ],
  targets: [
    .target(name: "ReclaimCore"),
    .executableTarget(name: "Reclaim", dependencies: ["ReclaimCore"]),
    .executableTarget(name: "reclaim-cli", dependencies: ["ReclaimCore"]),
    .testTarget(name: "ReclaimCoreTests", dependencies: ["ReclaimCore"]),
  ]
)
