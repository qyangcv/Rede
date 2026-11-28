// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Uchardet",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "CUchardet", targets: ["CUchardet"]),
    ],
    targets: [
        .target(
            name: "CUchardet",
            path: "Sources/CUchardet",
            exclude: [
                "src/Big5Freq.tab",
                "src/EUCKRFreq.tab",
                "src/EUCTWFreq.tab",
                "src/GB2312Freq.tab",
                "src/JISFreq.tab",
            ],
            sources: ["src"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("include"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx11
)
