import Foundation

struct UpdateChecks {
    func launchModes() {
        XCTAssertTrue(UpdateLaunchPolicy.shouldStart(arguments: ["AgentNotch"]))
        XCTAssertTrue(UpdateLaunchPolicy.shouldStart(arguments: ["AgentNotch", "--open-list"]))
        for flag in ["--fixture", "--snapshot", "--snapshot-card", "--snapshot-settings", "--snapshot-live", "--install-hooks", "--uninstall-hooks"] {
            XCTAssertFalse(UpdateLaunchPolicy.shouldStart(arguments: ["AgentNotch", flag, "test"]))
        }
    }
}
