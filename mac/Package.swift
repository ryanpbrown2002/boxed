// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "boxed",
  platforms: [.macOS(.v13)],
  targets: [
    // Pure, testable layout math — no AppKit / window APIs.
    .target(name: "BoxedKit", path: "Sources/BoxedKit"),
    // The menubar app.
    .executableTarget(name: "boxed", dependencies: ["BoxedKit"], path: "Sources/boxed"),
    // Unit tests for the layout math (run with Xcode's toolchain).
    .testTarget(name: "BoxedKitTests", dependencies: ["BoxedKit"], path: "Tests/BoxedKitTests")
  ]
)
