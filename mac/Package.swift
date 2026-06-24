// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "boxed",
  platforms: [.macOS(.v13)],
  targets: [
    .executableTarget(
      name: "boxed",
      path: "Sources/boxed"
    )
  ]
)
