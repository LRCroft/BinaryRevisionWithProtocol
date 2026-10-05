// swift-tools-version: 5.9.2
import PackageDescription

let package = Package(
    name: "VSN",
    targets: [
        .target(name: "VSN", path: ".", sources: ["Vsn.swift"]),
        .testTarget(name: "VSNTests", dependencies: ["VSN"], path: ".", sources: ["VsnTests.swift"])
    ]
)
