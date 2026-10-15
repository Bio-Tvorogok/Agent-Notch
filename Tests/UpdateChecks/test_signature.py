from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ArchiveSignatureChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory()
        cls.directory = Path(cls.workspace.name)
        cls.verifier = cls.directory / "verify"
        cls.fixture = cls.directory / "fixture"
        for source, output in [(ROOT / "scripts/verify-update-signature.swift", cls.verifier), (ROOT / "Tests/UpdateChecks/make-test-signature.swift", cls.fixture)]:
            subprocess.run(["xcrun", "swiftc", str(source), "-o", str(output)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.workspace.cleanup()

    def test_corrupt_archive_or_wrong_key_is_rejected(self):
        first = self.directory / "first"
        second = self.directory / "second"
        first.mkdir()
        second.mkdir()
        public, signature = subprocess.check_output([str(self.fixture), str(first)], text=True).splitlines()
        other, _ = subprocess.check_output([str(self.fixture), str(second)], text=True).splitlines()
        archive = first / "archive.zip"
        def verify(key):
            return subprocess.run([str(self.verifier), key, signature, str(archive)], capture_output=True).returncode
        self.assertEqual(verify(public), 0)
        self.assertNotEqual(verify(other), 0)
        archive.write_bytes(b"tampered update archive")
        self.assertNotEqual(verify(public), 0)

if __name__ == "__main__":
    unittest.main()
