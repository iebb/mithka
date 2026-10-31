// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "mithka_proxy",
  platforms: [
    .iOS("15.0"),
    .macOS("12.0"),
  ],
  products: [
    .library(name: "mithka-proxy", targets: ["mithka_proxy"])
  ],
  dependencies: [],
  targets: [
    .target(name: "mithka_proxy", dependencies: [])
  ]
)
