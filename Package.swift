// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopySaver",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CopySaverDomain", targets: ["CopySaverDomain"]),
        .library(name: "CopySaverVault", targets: ["CopySaverVault"]),
    ],
    targets: [
        .target(name: "CopySaverDomain"),
        .target(
            name: "CopySaverVault",
            dependencies: ["CopySaverDomain"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "CopySaverDomainTests", dependencies: ["CopySaverDomain"]),
        .testTarget(
            name: "CopySaverVaultTests", dependencies: ["CopySaverVault", "CopySaverDomain"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
