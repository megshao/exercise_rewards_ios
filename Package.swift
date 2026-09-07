// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExerciseRewardsKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ExerciseRewardsKit", targets: ["ExerciseRewardsKit"])
    ],
    targets: [
        .target(name: "ExerciseRewardsKit"),
        .testTarget(name: "ExerciseRewardsKitTests", dependencies: ["ExerciseRewardsKit"], resources: [.copy("Fixtures")])
    ]
)
