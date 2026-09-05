// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SportsRewardsKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SportsRewardsKit", targets: ["SportsRewardsKit"])
    ],
    targets: [
        .target(name: "SportsRewardsKit"),
        .testTarget(name: "SportsRewardsKitTests", dependencies: ["SportsRewardsKit"], resources: [.copy("Fixtures")])
    ]
)
