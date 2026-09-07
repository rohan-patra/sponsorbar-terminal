// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "SponsorBarTerminal",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "sponsorbar-terminal", targets: ["SponsorBarTerminal"])
  ],
  targets: [
    .executableTarget(name: "SponsorBarTerminal"),
    .testTarget(
      name: "SponsorBarTerminalTests",
      dependencies: ["SponsorBarTerminal"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
