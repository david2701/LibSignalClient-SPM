// swift-tools-version: 5.9
import PackageDescription

// Upstream signalapp/libsignal version this release tracks. Keep in sync with the tag,
// the `SignalFfi` binaryTarget URL, and Sources/LibSignalClient (all set by scripts/build-xcframework.sh).
let libsignalVersion = "0.79.1"

let package = Package(
    name: "LibSignalClient",
    platforms: [.iOS(.v13), .macOS(.v11)],
    products: [
        .library(name: "LibSignalClient", targets: ["LibSignalClient"]),
    ],
    targets: [
        // Prebuilt Rust FFI (BoringSSL + libsignal), built from source with NO bitcode so it can be
        // packaged as an xcframework (Signal's own prebuilt cannot). Produced + uploaded by CI.
        .binaryTarget(
            name: "SignalFfi",
            url: "https://github.com/david2701/LibSignalClient-SPM/releases/download/0.79.1/SignalFfi.xcframework.zip",
            checksum: "a1e3826f86e77f69a18677eaebbab922e898d23ab41eda03a7a4490e24cb87c8" // set by scripts/build-xcframework.sh
        ),
        .target(
            name: "LibSignalClient",
            dependencies: ["SignalFfi"],
            path: "Sources/LibSignalClient"
        ),
    ]
)
