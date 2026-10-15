#!/usr/bin/env python3
"""Validate updater configuration before writing the app's Info.plist."""
import base64
import binascii
import os
from pathlib import Path
import plistlib
import re
import sys
from urllib.parse import urlparse

FEED = "https://github.com/Forichok/Agent-Notch/releases/latest/download/appcast.xml"

def configure(path):
    info = plistlib.loads(path.read_bytes())
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ValueError("updates require a stable X.Y.Z version")
    key_file = Path(__file__).resolve().parents[1] / "packaging/updates-public-key.txt"
    key = os.environ.get("UPDATE_PUBLIC_KEY", key_file.read_text().strip() if key_file.exists() else "")
    try:
        valid_key = len(base64.b64decode(key, validate=True)) == 32
    except (ValueError, binascii.Error):
        valid_key = False
    if not valid_key:
        raise ValueError("UPDATE_PUBLIC_KEY must contain a base64 Ed25519 public key (32 bytes)")
    test = os.environ.get("UPDATE_TEST_BUNDLE") == "1"
    feed = os.environ.get("UPDATE_FEED_URL", FEED)
    if test:
        url = urlparse(feed)
        if not (url.scheme == "http" and url.hostname in ("127.0.0.1", "localhost") and not url.username and not url.password):
            raise ValueError("test feed must use HTTP on localhost")
        info["CFBundleIdentifier"] = "com.forichok.agents-notch.updater-test"
        info["CFBundleName"] = info["CFBundleDisplayName"] = "Agent Notch Update Test"
        info["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
    elif feed != FEED:
        raise ValueError("production feed must use the stable Agent Notch GitHub Releases URL")
    # Marketing versions, rather than CI run numbers, order local and release builds identically.
    info.update(CFBundleVersion=version, SUPublicEDKey=key, SUFeedURL=feed,
                SUEnableAutomaticChecks=True, SUScheduledCheckInterval=86400,
                SUAllowsAutomaticUpdates=False, SUAutomaticallyUpdate=False,
                SUVerifyUpdateBeforeExtraction=True, SUEnableSystemProfiling=False)
    path.write_bytes(plistlib.dumps(info, sort_keys=False))

if __name__ == "__main__":
    try:
        configure(Path(sys.argv[1]))
    except (ValueError, KeyError, OSError, IndexError) as error:
        sys.exit("update configuration: " + str(error))
