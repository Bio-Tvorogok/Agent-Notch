import AppKit
enum RoomWallpaper { static let pinchPermissionChanged = Notification.Name("AgentsNotch.housePinchPermissionChanged") }
@main struct PermissionChecks {
    @MainActor static func main() {
        func expect(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
        var requests = 0, notifications = 0
        var opened: [String] = []
        func enable(requestResult: Bool, allowed: Bool) -> Bool {
            HousePinchPermission.enable(request: { requests += 1; return requestResult },
                                        preflight: { allowed }, openSettings: { opened.append($0.absoluteString) },
                                        changed: { notifications += 1 })
        }
        expect(!enable(requestResult: false, allowed: false), "previous denial remains denied")
        expect(opened == ["x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"], "denial opens Input Monitoring")
        opened = []
        expect(!enable(requestResult: true, allowed: false), "request result alone cannot establish access")
        expect(opened.count == 1, "unconfirmed permission still opens settings")
        opened = []
        expect(enable(requestResult: false, allowed: true), "preflight is authoritative after request")
        expect(opened.isEmpty, "granted access does not open settings")
        expect(requests == 3 && notifications == 3, "each explicit request refreshes the tap")
        expect(HousePinchPermission.refresh(preflight: { true }, changed: { notifications += 1 }), "activation/row refresh detects a grant")
        expect(!HousePinchPermission.refresh(preflight: { false }, changed: { notifications += 1 }), "refresh detects revocation")
        expect(requests == 3 && notifications == 5, "passive refresh notifies the tap without requesting access")
        print("OK denied pinch permission fallback and refresh")
    }
}
