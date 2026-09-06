#!/usr/bin/env python3
"""Copy the local Token Factory key into the built app. Never commit backend/.env."""

import os
import plistlib
from pathlib import Path


def read_key(srcroot: Path) -> str:
    env_file = srcroot / "backend" / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            if line.startswith("NEBIUS_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"')
    xcconfig = srcroot / "Config" / "Secrets.xcconfig"
    if xcconfig.exists():
        for line in xcconfig.read_text().splitlines():
            if line.startswith("NEBIUS_API_KEY"):
                return line.split("=", 1)[1].strip().strip('"')
    return os.environ.get("NEBIUS_API_KEY", "").strip()


def write_plist(path: Path, payload: dict) -> None:
    existing = {}
    if path.exists():
        with path.open("rb") as handle:
            existing = plistlib.load(handle)
    existing.update(payload)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        plistlib.dump(existing, handle)


def main() -> None:
    srcroot = Path(os.environ.get("SRCROOT", ".")).resolve()
    key = read_key(srcroot)
    if not key:
        print("warning: NEBIUS_API_KEY not found in backend/.env")
        return

    build_dir = Path(os.environ["TARGET_BUILD_DIR"])
    info_plist = build_dir / os.environ["INFOPLIST_PATH"]
    if info_plist.exists():
        write_plist(info_plist, {"NEBIUS_API_KEY": key})

    resources = os.environ.get("UNLOCALIZED_RESOURCES_FOLDER_PATH")
    if resources:
        write_plist(build_dir / resources / "NebiusSecrets.plist", {"NEBIUS_API_KEY": key})


if __name__ == "__main__":
    main()
