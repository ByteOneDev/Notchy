// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Notchy",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Notchy",
            path: "Sources/Notchy",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("EventKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
