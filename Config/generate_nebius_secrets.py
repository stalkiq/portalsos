#!/usr/bin/env python3
"""Write a local Swift secrets file from backend/.env so the Simulator always has the key."""

from pathlib import Path
import os


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


def main() -> None:
    srcroot = Path(os.environ.get("SRCROOT") or Path(__file__).resolve().parents[1]).resolve()
    out_dir = srcroot / "Sources" / "Generated"
    out_dir.mkdir(parents=True, exist_ok=True)
    key = read_key(srcroot)
    escaped = key.replace("\\", "\\\\").replace('"', '\\"')
    (out_dir / "NebiusLocalSecrets.swift").write_text(
        "enum NebiusLocalSecrets {\n"
        f'    static let apiKey = "{escaped}"\n'
        "}\n"
    )
    print("wrote NebiusLocalSecrets.swift", "key_len", len(key))


if __name__ == "__main__":
    main()
