// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyboardSwitcher",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "KeyboardSwitcher", targets: ["KeyboardSwitcher"])],
    targets: [
        .target(name: "SwitcherCore"),
        .executableTarget(name: "KeyboardSwitcher", dependencies: ["SwitcherCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SwitcherCoreTests", dependencies: ["SwitcherCore"])
    ]
)
