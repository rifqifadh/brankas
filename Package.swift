// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Brankas",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Brankas", targets: ["Brankas"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Brankas",
            dependencies: []
        )
    ]
)
