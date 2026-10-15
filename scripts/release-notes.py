#!/usr/bin/env python3
"""Extract only the requested stable changelog section before a release build."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def release_notes(version):
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ValueError("release requires a stable X.Y.Z version")
    lines = (ROOT / "CHANGELOG.md").read_text().splitlines()
    selected = []
    active = False
    for line in lines:
        if line.startswith("## "):
            if active:
                break
            active = re.match(r"^## \[" + re.escape(version) + r"\](?: |$)", line) is not None
        elif active and not re.match(r"^\[[^]]+\]:", line):
            selected.append(line)
    notes = "\n".join(selected).strip()
    if not notes or not any(line.strip() and not line.startswith("#") for line in selected):
        raise ValueError("CHANGELOG.md has no release notes for " + version)
    return notes + "\n\n" + (ROOT / "packaging/install-notes.md").read_text().strip() + "\n"

if __name__ == "__main__":
    try:
        print(release_notes(sys.argv[1]), end="")
    except (ValueError, IndexError, OSError) as error:
        sys.exit(str(error))
