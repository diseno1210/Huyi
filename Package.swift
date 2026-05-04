// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LocalScreenTranslator",
    platforms: [
        .macOS("15.2")
    ],
    products: [
        .executable(name: "LocalScreenTranslator", targets: ["LocalScreenTranslator"])
    ],
    targets: [
        .executableTarget(
            name: "LocalScreenTranslator",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Translation"),
                .linkedFramework("Vision")
            ]
        )
    ]
)
