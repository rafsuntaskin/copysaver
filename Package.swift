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
        .library(name: "CopySaverWidgets", targets: ["CopySaverWidgets"]),
        .executable(name: "CopySaverDev", targets: ["CopySaverDev"]),
        .executable(name: "CopySaverWidgetCheck", targets: ["CopySaverWidgetCheck"]),
        .executable(name: "CopySaverCrashProbe", targets: ["CopySaverCrashProbe"]),
        .executable(name: "CopySaverKeychainProbe", targets: ["CopySaverKeychainProbe"]),
        .executable(name: "CopySaverAutomaticVaultProbe", targets: ["CopySaverAutomaticVaultProbe"]),
    ],
    targets: [
        .target(name: "CopySaverDomain"),
        .executableTarget(name: "CopySaverAutomaticVaultProbe", dependencies: ["CopySaverPlatform", "CopySaverDomain", "CopySaverVault"], path: "TestsSupport/AutomaticVaultProbe"),
        .executableTarget(name: "CopySaverCrashProbe", dependencies: ["CopySaverDomain", "CopySaverVault"], path: "TestsSupport/CrashProbe"),
        .executableTarget(name: "CopySaverKeychainProbe", dependencies: ["CopySaverPlatform", "CopySaverDomain", "CopySaverVault"], path: "TestsSupport/KeychainProbe", exclude: ["Info.plist", "CopySaverKeychainProbe.entitlements"]),
        .target(name: "CopySaverWidgets"),
        .executableTarget(name: "CopySaverWidgetCheck", dependencies: ["CopySaverWidgets"], path: "Widget", exclude: ["Info.plist", "CopySaverWidget.entitlements"]),
        .testTarget(name: "CopySaverWidgetsTests", dependencies: ["CopySaverWidgets", "CopySaverPlatform"]),
        .target(
            name: "CopySaverVault",
            dependencies: ["CopySaverDomain"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "CopySaverDomainTests", dependencies: ["CopySaverDomain"]),
        .target(name: "CopySaverPlatform", dependencies: ["CopySaverDomain", "CopySaverVault"]),
        .target(name: "CopySaverDesktop", dependencies: ["CopySaverDomain", "CopySaverVault", "CopySaverPlatform"]),
        .executableTarget(name: "CopySaverDev", dependencies: ["CopySaverDesktop"], path: "App", exclude: ["Info.plist", "CopySaver.entitlements", "CopySaverPreview.entitlements"]),
        .testTarget(name: "CopySaverPlatformTests", dependencies: ["CopySaverPlatform", "CopySaverDomain", "CopySaverVault"]),
        .testTarget(name: "CopySaverDesktopTests", dependencies: ["CopySaverDesktop", "CopySaverDomain", "CopySaverPlatform", "CopySaverVault"]),
        .testTarget(
            name: "CopySaverVaultTests", dependencies: ["CopySaverVault", "CopySaverDomain"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
