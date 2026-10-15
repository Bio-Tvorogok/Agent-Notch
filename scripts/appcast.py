#!/usr/bin/env python3
"""Generate a signed stable feed from the final ZIP; never expose private keys."""
import base64
import html
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"

def generate(version, directory, notes, sparkle):
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ValueError("feed requires a stable X.Y.Z version")
    archive = directory / ("AgentNotch-" + version + ".zip")
    if not archive.is_file():
        raise ValueError("missing release ZIP: " + str(archive))
    with zipfile.ZipFile(archive) as zipped:
        candidates = [p for p in zipped.namelist() if p.endswith(".app/Contents/Info.plist") and len(p.split("/")) == 3]
        if len(candidates) != 1:
            raise ValueError("release ZIP must contain one app bundle")
        info = plistlib.loads(zipped.read(candidates[0]))
    if info.get("CFBundleVersion") != version or info.get("CFBundleShortVersionString") != version:
        raise ValueError("release ZIP version does not match requested release")
    key = info.get("SUPublicEDKey", "")
    if len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError("release ZIP has no valid update public key")
    test = info.get("CFBundleIdentifier") == "com.forichok.agents-notch.updater-test"
    if test:
        from urllib.parse import urlparse
        feed = info["SUFeedURL"]
        url = urlparse(feed)
        if url.scheme != "http" or url.hostname not in ("127.0.0.1", "localhost"):
            raise ValueError("invalid isolated test feed")
        prefix = feed.rsplit("/", 1)[0] + "/"
    else:
        if info.get("CFBundleIdentifier") != "com.forichok.agents-notch":
            raise ValueError("unexpected bundle identifier")
        prefix = "https://github.com/Forichok/Agent-Notch/releases/download/v" + version + "/"
    with tempfile.TemporaryDirectory(prefix="notch-appcast-") as temporary:
        stage = Path(temporary)
        shutil.copy2(archive, stage / archive.name)
        (stage / (archive.stem + ".html")).write_text("<pre>" + html.escape(notes.read_text()) + "</pre>")
        command = [str(sparkle / "bin/generate_appcast"), "--embed-release-notes", "--maximum-deltas", "0", "--download-url-prefix", prefix]
        secret = os.environ.get("SPARKLE_PRIVATE_KEY")
        if secret:
            command += ["--ed-key-file", "-"]
        else:
            command += ["--account", "com.forichok.agents-notch"]
        command += [str(stage)]
        subprocess.run(command, input=secret, text=True, check=True)
        feed = stage / "appcast.xml"
        tree = ET.parse(feed)
        items = tree.findall("./channel/item")
        if len(items) != 1 or items[0].findtext("{" + NS + "}version") != version:
            raise ValueError("generated feed must contain exactly the requested version")
        enclosure = items[0].find("enclosure")
        if enclosure is None or enclosure.get("url") != prefix + archive.name or enclosure.get("length") != str(archive.stat().st_size):
            raise ValueError("generated feed has incorrect archive metadata")
        signature = enclosure.get("{" + NS + "}edSignature", "")
        verifier = ROOT / ".build/checks/verify-update-signature"
        verifier.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["xcrun", "swiftc", str(ROOT / "scripts/verify-update-signature.swift"), "-o", str(verifier)], check=True)
        subprocess.run([str(verifier), key, signature, str(archive)], check=True)
        shutil.copy2(feed, directory / "appcast.xml")

if __name__ == "__main__":
    try:
        generate(sys.argv[1], Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve(), Path(sys.argv[4]).resolve())
    except (ValueError, OSError, KeyError, IndexError, zipfile.BadZipFile, ET.ParseError, subprocess.CalledProcessError) as error:
        sys.exit("appcast: " + str(error))
