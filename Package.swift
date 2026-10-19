// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ember",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Ember",
            resources: [.copy("Resources/pricing.json")],
            swiftSettings: []
        )
    ]
)
