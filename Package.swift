// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DisplayVolumeKeys",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DisplayVolumeKeys", targets: ["DisplayVolumeKeys"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/waydabber/AppleSiliconDDC.git",
            revision: "67ff964ab8123d9d35fadf7d8e1a7c677d31da14"
        ),
    ],
    targets: [
        .target(
            name: "OSDPrivate",
            path: "Sources/OSDPrivate",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
                .linkedFramework("OSD"),
            ]
        ),
        .executableTarget(
            name: "DisplayVolumeKeys",
            dependencies: [
                "OSDPrivate",
                .product(name: "AppleSiliconDDC", package: "AppleSiliconDDC"),
            ],
            path: "Sources/DisplayVolumeKeys",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
