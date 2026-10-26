// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopySaver",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CopySaverDomain", targets: ["CopySaverDomain"]),
        .library(name: "CopySaverVault", targets: ["CopySaverVault"]),
        .library(name: "CopySaverPlatform", targets: ["CopySaverPlatform"]),
        .library(name: "CopySaverDesktop", targets: ["CopySaverDesktop"]),
        .executable(name: "CopySaverDev", targets: ["CopySaverDev"]),
    ],
    targets: [
        .target(name: "CopySaverDomain"),
        .target(
            name: "CopySaverVault",
            dependencies: ["CopySaverDomain"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "CopySaverDomainTests", dependencies: ["CopySaverDomain"]),
        .target(name: "CopySaverPlatform", dependencies: ["CopySaverDomain", "CopySaverVault"]),
        .target(name: "CopySaverDesktop", dependencies: ["CopySaverDomain", "CopySaverVault", "CopySaverPlatform"]),
        .executableTarget(name: "CopySaverDev", dependencies: ["CopySaverDesktop"], path: "App", exclude: ["Info.plist", "CopySaver.entitlements"]),
        .testTarget(name: "CopySaverPlatformTests", dependencies: ["CopySaverPlatform", "CopySaverDomain", "CopySaverVault"]),
        .testTarget(name: "CopySaverDesktopTests", dependencies: ["CopySaverDesktop", "CopySaverDomain", "CopySaverPlatform", "CopySaverVault"]),
        .testTarget(
            name: "CopySaverVaultTests", dependencies: ["CopySaverVault", "CopySaverDomain"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
