// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WavReader",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "WavReader",
            targets: ["WavReader"]),
        // Answers "do these two files hold the same audio, as far as this package's readers are
        // concerned" — the check a corpus conversion has to pass before it is trusted.
        .executable(
            name: "audio-file-compare",
            targets: ["AudioFileCompare"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "WavReader",
            dependencies: ["CWavHeader", "CDrFlac"]),
        .target(name: "CWavHeader"),
        // dr_flac, vendored: a single-file public-domain FLAC decoder. Vendored rather than linked
        // against the system libFLAC because this package builds on macOS through SwiftPM and on
        // Linux through a CMake tree that has no package manager to install a system library from.
        .target(name: "CDrFlac"),
        .executableTarget(
            name: "AudioFileCompare",
            dependencies: ["WavReader"]),
        .testTarget(
            name: "WavReaderTests",
            dependencies: ["WavReader"]),
    ]
)
