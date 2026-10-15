import base64
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
KEY = base64.b64encode(bytes(range(32))).decode()

class UpdateConfigChecks(unittest.TestCase):
    def run_config(self, **overrides):
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / "Info.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.forichok.agents-notch", "CFBundleShortVersionString": "0.4.0", "CFBundleVersion": "99999"}))
            env = {k: v for k, v in os.environ.items() if not k.startswith(("UPDATE_", "SPARKLE_"))}
            env.update(UPDATE_PUBLIC_KEY=KEY)
            env.update(overrides)
            result = subprocess.run(["python3", str(ROOT / "scripts/update-config.py"), str(plist)], env=env, capture_output=True, text=True)
            return result, plistlib.loads(plist.read_bytes())

    def test_updates_require_valid_signing_key(self):
        for key in ["", "broken", base64.b64encode(b"short").decode()]:
            result, _ = self.run_config(UPDATE_PUBLIC_KEY=key)
            self.assertNotEqual(result.returncode, 0)

    def test_updates_only_run_after_user_action(self):
        result, info = self.run_config()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(info["SUFeedURL"], "https://github.com/Forichok/Agent-Notch/releases/latest/download/appcast.xml")
        self.assertEqual(info["SUPublicEDKey"], KEY)
        self.assertFalse(info["SUEnableAutomaticChecks"])
        self.assertFalse(info["SUAllowsAutomaticUpdates"])
        self.assertFalse(info["SUAutomaticallyUpdate"])
        self.assertTrue(info["SUVerifyUpdateBeforeExtraction"])
        self.assertEqual(info["CFBundleVersion"], "0.4.0")

    def test_production_rejects_insecure_or_foreign_feed(self):
        for url in ["http://localhost:9000/appcast.xml", "file:///tmp/appcast.xml", "https://example.org/appcast.xml"]:
            result, _ = self.run_config(UPDATE_FEED_URL=url)
            self.assertNotEqual(result.returncode, 0)

    def test_isolated_test_bundle_allows_local_feed(self):
        result, info = self.run_config(UPDATE_TEST_BUNDLE="1", UPDATE_FEED_URL="http://127.0.0.1:9000/appcast.xml")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(info["CFBundleIdentifier"], "com.forichok.agents-notch.updater-test")
        self.assertEqual(info["SUFeedURL"], "http://127.0.0.1:9000/appcast.xml")

if __name__ == "__main__":
    unittest.main()
