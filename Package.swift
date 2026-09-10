// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DuoLid",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DuoLid", targets: ["DuoLid"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .target(name: "DuoLidCore"),
        .executableTarget(
            name: "DuoLid",
            dependencies: ["DuoLidCore", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources/Effects.metal")],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("IOKit"),
                .linkedFramework("ScreenCaptureKit"), .linkedFramework("MetalKit"),
                .linkedFramework("MetalPerformanceShaders"),
                .linkedFramework("AVFoundation"), .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "DuoLidCoreTests", dependencies: ["DuoLidCore"]),
    ],
    swiftLanguageModes: [.v6]
)
