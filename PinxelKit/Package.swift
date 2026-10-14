// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinxelKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DocumentModel", targets: ["DocumentModel"]),
        .library(name: "Rendering", targets: ["Rendering"]),
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    targets: [
        .target(name: "DocumentModel"),
        .target(name: "Rendering", dependencies: ["DocumentModel"]),
        .target(name: "Persistence", dependencies: ["DocumentModel", "Rendering"]),
        .target(
            name: "PinxelTestSupport",
            dependencies: ["DocumentModel"],
            path: "Tests/PinxelTestSupport"
        ),
        .testTarget(
            name: "DocumentModelTests",
            dependencies: ["DocumentModel", "PinxelTestSupport"]
        ),
        .testTarget(
            name: "RenderingTests",
            dependencies: ["Rendering", "PinxelTestSupport"],
            exclude: ["__Snapshots__"]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "PinxelTestSupport"]
        ),
    ]
)
