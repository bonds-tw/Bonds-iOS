// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenACAgeSwift",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "OpenACAgeSwift", targets: ["OpenACAgeSwift"]),
    ],
    targets: [
        .binaryTarget(
            name: "openac_age_mobile_appFFI",
            url: "https://github.com/bonds-tw/backupTW-iOS/releases/download/openac-field-v2/OpenACFieldBindings.xcframework.zip",
            checksum: "7bd13bc83621d87e7a5f866518f3513f5fe5ed2fe03e4c46e6f9e9f51bff4776"),
        .target(
            name: "OpenACAgeSwift",
            dependencies: ["openac_age_mobile_appFFI", "COpenACAgeFFI"],
            path: "Sources/OpenACAgeSwift",
            linkerSettings: [.linkedLibrary("c++")]),
        // Xcode 26 does not expose the module map of a static-library
        // XCFramework to Swift. Register the binary header as a real Clang
        // module so UniFFI's generated Swift can import its C declarations.
        .target(
            name: "COpenACAgeFFI",
            dependencies: ["openac_age_mobile_appFFI"],
            path: "Sources/COpenACAgeFFI",
            publicHeadersPath: "include"),
    ])
