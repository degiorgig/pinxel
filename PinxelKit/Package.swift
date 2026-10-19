// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinxelKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DocumentModel", targets: ["DocumentModel"]),
        .library(name: "Rendering", targets: ["Rendering"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "CaptureKit", targets: ["CaptureKit"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "EditorUI", targets: ["EditorUI"]),
        .library(name: "Library", targets: ["Library"]),
    ],
    targets: [
        .target(name: "DocumentModel"),
        .target(name: "Rendering", dependencies: ["DocumentModel"]),
        .target(name: "Persistence", dependencies: ["DocumentModel", "Rendering"]),
        // La cucitura della cattura a scorrimento confronta milioni di pixel a fotogramma: senza ottimizzazioni è
        // dieci volte più lenta e, scorrendo a mano, perde i passaggi.
        .target(name: "CaptureKit", swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .target(name: "AppCore", dependencies: ["DocumentModel", "Rendering", "Persistence"]),
        .target(name: "EditorUI", dependencies: ["DocumentModel", "Rendering"]),
        .target(name: "Library", dependencies: ["DocumentModel", "Persistence", "AppCore"]),
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
            dependencies: ["Persistence", "AppCore", "PinxelTestSupport"]
        ),
        .testTarget(
            name: "CaptureKitTests",
            dependencies: ["CaptureKit", "PinxelTestSupport"]
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore", "PinxelTestSupport"]
        ),
        .testTarget(
            name: "LibraryTests",
            dependencies: ["Library", "AppCore", "Persistence", "PinxelTestSupport"]
        ),
        .testTarget(
            name: "EditorUITests",
            dependencies: ["EditorUI", "DocumentModel", "Rendering", "PinxelTestSupport"]
        ),
    ]
)
