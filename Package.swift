// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Spectrum",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Spectrum",
            path: "Sources/Spectrum",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
