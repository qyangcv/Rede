// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LibMobi",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "CLibMobi", targets: ["CLibMobi"]),
    ],
    targets: [
        .target(
            name: "CLibMobi",
            path: "Sources/CLibMobi",
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                .define("HAVE_CONFIG_H", to: "1"),
                .define("USE_XMLWRITER", to: "1"),
                .define("USE_LIBXML2", to: "1"),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("xml2"),
            ]
        ),
    ]
)
