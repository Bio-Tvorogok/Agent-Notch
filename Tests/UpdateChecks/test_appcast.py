import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class AppcastChecks(unittest.TestCase):
    def test_missing_archive_fails_before_signing(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(["python3", str(ROOT / "scripts/appcast.py"), "0.5.0", directory, str(Path(directory) / "notes.md"), str(ROOT / ".build/sparkle/2.10.0")], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing release ZIP", result.stderr)
            self.assertFalse((Path(directory) / "appcast.xml").exists())

    def test_prerelease_is_not_published_in_stable_feed(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(["python3", str(ROOT / "scripts/appcast.py"), "0.5.0-beta.1", directory, "notes.md", "sparkle"], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stable X.Y.Z", result.stderr)

if __name__ == "__main__":
    unittest.main()
