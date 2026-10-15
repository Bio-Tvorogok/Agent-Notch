// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AgentsNotch",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        // Pure logic: reading Claude Code and Codex session logs, hooks, the agent tree, the wing layout.
        .target(name: "NotchCore"),
        // AppKit + SwiftUI shell: the wing beside the notch, the list panel, hotkeys.
        .executableTarget(name: "AgentsNotch", dependencies: ["NotchCore", .product(name: "Sparkle", package: "Sparkle")]),
        // notch-hook: what Claude Code and Codex run for each hook event.
        .executableTarget(name: "NotchHook", dependencies: ["NotchCore"]),
        // Framework-free checks (Command Line Tools ship no XCTest): scripts/test.sh or `swift run CoreChecks`.
        .executableTarget(name: "CoreChecks", dependencies: ["NotchCore"], path: "Tests/CoreChecks"),
    ]
)
