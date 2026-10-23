import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

struct HousePinchChecks {
    func all() throws {
        let off = HousePinch.statusLine(allowed: false, created: nil)
        XCTAssertTrue(off.contains("not granted") && off.contains("not created") && off.contains("Esc"), "no permission: says so and what still works")
        XCTAssertTrue(HousePinch.statusLine(allowed: true, created: true, enabled: true).hasSuffix("created, enabled=true"), "tap created and enabled")
        XCTAssertTrue(HousePinch.statusLine(allowed: true, created: false).contains("tapCreate failed"), "tap refused")
        XCTAssertTrue(HousePinch.hintDue(tapActive: false, alreadyShown: false, zoomTarget: 2.4), "zoomed in by click, no tap: hint")
        XCTAssertTrue(!HousePinch.hintDue(tapActive: true, alreadyShown: false, zoomTarget: 2.4), "tap works: no hint")
        XCTAssertTrue(!HousePinch.hintDue(tapActive: false, alreadyShown: true, zoomTarget: 2.4), "only once")
        XCTAssertTrue(!HousePinch.hintDue(tapActive: false, alreadyShown: false, zoomTarget: 1), "overview: no hint")
        XCTAssertTrue(HousePinch.cause(allowed: false) == .notGranted && HousePinch.cause(allowed: true) == .tapFailed, "the hint names the real cause")
        print("housePinchChecks: status lines, hint due")
    }
}
