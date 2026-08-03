// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftSH",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "SwiftSH", targets: ["SwiftSH"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/migueldeicaza/Libssh2Prebuild.git",
            revision: "242b5e3746076f93a284df21a2af4567fcae094a"
        )
    ],
    targets: [
        .target(
            name: "CSwiftSH",
            dependencies: [.product(name: "CSSH", package: "Libssh2Prebuild")]
        ),
        .target(
            name: "SwiftSH",
            dependencies: [
                .product(name: "CSSH", package: "Libssh2Prebuild"),
                "CSwiftSH"
            ]
        )
    ]
)
