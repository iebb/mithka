#!/usr/bin/env python3
"""Verify the signed macOS media capabilities and primary icon before shipping."""

import json
import plistlib
import subprocess
import sys
from pathlib import Path


app = Path(sys.argv[1])
contents = app / "Contents"
info = plistlib.loads((contents / "Info.plist").read_bytes())
if info.get("CFBundleIconName") != "Pengram":
    raise SystemExit("macOS must ship the Pengram Liquid Glass primary icon")
resources = contents / "Resources"
subprocess.run(
    [
        sys.executable,
        str(Path(__file__).with_name("macos-small-icon-fallback.py")),
        "--check",
        str(resources / "Pengram.icns"),
        "macos/Runner/Assets.xcassets/AppIcon.appiconset",
    ],
    check=True,
)
renditions = json.loads(
    subprocess.check_output(["xcrun", "assetutil", "--info", str(resources / "Assets.car")])
)
if not any(
    rendition.get("Name") == "Pengram"
    and rendition.get("AssetType") == "IconImageStack"
    for rendition in renditions
):
    raise SystemExit("macOS bundle has no Pengram Liquid Glass layers")
entitlements = plistlib.loads(
    subprocess.check_output(
        ["codesign", "-d", "--entitlements", ":-", str(app)],
        stderr=subprocess.DEVNULL,
    )
)
for capability in ("app-sandbox", "network.client", "network.server"):
    if entitlements.get(f"com.apple.security.{capability}") is not True:
        raise SystemExit(f"signed macOS app lacks required capability: {capability}")
print("Verified signed sandbox, loopback streaming, Liquid Glass and small icon fallbacks")
