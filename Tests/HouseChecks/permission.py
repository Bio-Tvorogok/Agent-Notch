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
        self.assertEqual(source.count('CGRequestListenEventAccess()'), 1)
        action = source[source.index('Button(HouseText.enablePinchZoom)'):]
        self.assertLess(action.index('CGRequestListenEventAccess()'), action.index('}'))

if __name__ == '__main__':
    unittest.main()
