// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "cs-tool-x",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CSToolX", targets: ["CSToolX"]),
      .executable(name: "cs-tool-x", targets: ["ToolCLI"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.20.0")
    ],
    targets: [
        .target(name: "ToolCore"),
        .executableTarget(name: "CSToolX", dependencies: ["ToolCore", .product(name: "Sparkle", package: "Sparkle"), .product(name: "SwiftTerm", package: "SwiftTerm")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "ToolCLI", dependencies: ["ToolCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "ToolCoreTests", dependencies: ["ToolCore"])
    ]
)
