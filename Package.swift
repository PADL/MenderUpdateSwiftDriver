// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "MenderUpdateSwiftDriver",
  platforms: [
    .macOS(.v13),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to
    // other packages.
    .library(
      name: "MenderUpdateSwiftDriver",
      targets: ["MenderUpdateSwiftDriver"]
    ),
    .executable(
      name: "mender-update-swift-driver",
      targets: ["MenderUpdateSwiftDriverWrapper"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.1.1"),
    .package(url: "https://github.com/apple/swift-log", from: "1.6.2"),
    .package(url: "https://github.com/apple/swift-system", from: "1.4.0"),
    .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.2.1"),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "MenderUpdateSwiftDriver",
      dependencies: [
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "SystemPackage", package: "swift-system"),
      ]
    ),
    .executableTarget(
      name: "MenderUpdateSwiftDriverWrapper",
      dependencies: ["MenderUpdateSwiftDriver"]
    ),
    .testTarget(
      name: "MenderUpdateSwiftDriverTests",
      dependencies: ["MenderUpdateSwiftDriver"]
    ),
  ]
)
