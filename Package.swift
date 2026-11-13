// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "cs-tool-x",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CSToolX", targets: ["CSToolX"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.20.0")
    ],
    targets: [
        .target(name: "ToolCore"),
        .executableTarget(name: "CSToolX", dependencies: ["ToolCore", .product(name: "Sparkle", package: "Sparkle"), .product(name: "SwiftTerm", package: "SwiftTerm")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "ToolCoreTests", dependencies: ["ToolCore"])
    ]
)
