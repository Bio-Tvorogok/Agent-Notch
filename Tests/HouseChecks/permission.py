from pathlib import Path
import unittest

class PinchPermissionChecks(unittest.TestCase):
    def test_wallpaper_never_requests_permission_or_polls_denial(self):
        source = Path('Sources/AgentsNotch/RoomWallpaper.swift').read_text()
        self.assertNotIn('CGRequestListenEventAccess', source)
        self.assertNotIn('pinchWatch', source)
        self.assertIn('CGPreflightListenEventAccess()', source)

    def test_settings_has_explicit_enable_action(self):
        source = Path('Sources/AgentsNotch/SettingsHouse.swift').read_text()
        self.assertIn('Button(HouseText.enablePinchZoom)', source)
        self.assertIn('HousePinchPermission.enable()', source)
        self.assertIn('NSApplication.didBecomeActiveNotification', source)
        self.assertIn('NSWindow.didBecomeKeyNotification', source)
        self.assertIn('.onAppear { refreshPinchPermission() }', source)

if __name__ == '__main__':
    unittest.main()
