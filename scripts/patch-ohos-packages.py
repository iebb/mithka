#!/usr/bin/env python3
"""Stage HarmonyOS-patched copies of pub packages that do not compile there.

The OHOS Flutter fork adds TargetPlatform.ohos, so a package with an
exhaustive `switch` over TargetPlatform fails to compile for HarmonyOS.
flutter_math_fork 0.7.4 has four such switches. This script downloads the
exact version pinned in pubspec.lock, verifies the archive against the
lockfile's sha256, adds `case TargetPlatform.ohos:` next to the Android-style
branch (the fork's own framework treats ohos like android/fuchsia), and
writes the result to .ohos-packages/<name>, which pubspec_overrides.ohos.yaml
points a path override at.

Every edit is anchored and must match exactly once; any drift in the
upstream source fails the build instead of shipping an unreviewed change.

Usage (repo root, after scripts/enable-ohos-plugins.sh apply and before
`flutter pub get`):
    python3 scripts/patch-ohos-packages.py [--archive PATH]
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

OUT_DIR = ".ohos-packages"

_ANDROID_LIKE = (
    "case TargetPlatform.windows:\n",
    "case TargetPlatform.windows:\n{indent}case TargetPlatform.ohos:\n",
)

# package -> {relative file: number of anchored edits expected}
PATCHES = {
    "flutter_math_fork": {
        "lib/src/widgets/selectable.dart": 2,
        "lib/src/render/layout/line_editable.dart": 1,
        "lib/src/widgets/selection/gesture_detector_builder_selectable.dart": 1,
    },
}


def die(message):
    print(f"patch-ohos-packages: {message}", file=sys.stderr)
    raise SystemExit(1)


def locked_package(lock_text, name):
    match = re.search(
        rf"^  {re.escape(name)}:\n((?:    .*\n)+)", lock_text, flags=re.MULTILINE
    )
    if match is None:
        die(f"{name} is not in pubspec.lock")
    block = match.group(1)
    fields = dict(re.findall(r'^\s+(sha256|url|version): "([^"]+)"$', block, re.M))
    for key in ("sha256", "url", "version"):
        if key not in fields:
            die(f"pubspec.lock entry for {name} has no {key}")
    return fields


def fetch_archive(name, locked, dest):
    hosts = []
    for host in (os.environ.get("PUB_HOSTED_URL"), locked["url"]):
        if host and host.rstrip("/") not in hosts:
            hosts.append(host.rstrip("/"))
    for host in hosts:
        meta_url = f"{host}/api/packages/{name}/versions/{locked['version']}"
        try:
            with urllib.request.urlopen(meta_url, timeout=60) as resp:
                archive_url = json.load(resp)["archive_url"]
            with urllib.request.urlopen(archive_url, timeout=300) as resp:
                data = resp.read()
        except Exception as error:  # try the next host
            print(f"patch-ohos-packages: {host} unavailable ({error})", file=sys.stderr)
            continue
        if hashlib.sha256(data).hexdigest() == locked["sha256"]:
            dest.write_bytes(data)
            return
        # Mirrors occasionally serve corrupt archives; fall back to the
        # lockfile's own host instead of trusting them.
        print(f"patch-ohos-packages: {host} served a wrong archive hash", file=sys.stderr)
    die(f"no host served {name} {locked['version']} with the locked sha256")


def patch_file(path, expected):
    text = path.read_text(encoding="utf-8")
    anchor, replacement = _ANDROID_LIKE
    pattern = re.compile(rf"^([ \t]*){re.escape(anchor)}", re.MULTILINE)
    matches = pattern.findall(text)
    if len(matches) != expected:
        die(f"{path}: expected {expected} anchored switch(es), found {len(matches)}")
    text = pattern.sub(
        lambda m: m.group(1) + replacement.format(indent=m.group(1)), text
    )
    path.write_text(text, encoding="utf-8")


def stage(name, files, archive, root):
    lock_text = (root / "pubspec.lock").read_text(encoding="utf-8")
    locked = locked_package(lock_text, name)
    out = root / OUT_DIR / name
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        tarball = tmp / "package.tar.gz"
        if archive is not None:
            tarball.write_bytes(Path(archive).read_bytes())
            if hashlib.sha256(tarball.read_bytes()).hexdigest() != locked["sha256"]:
                die(f"{archive} does not match the locked sha256 for {name}")
        else:
            fetch_archive(name, locked, tarball)
        staged = tmp / name
        staged.mkdir()
        subprocess.run(["tar", "xzf", str(tarball), "-C", str(staged)], check=True)
        for relative, expected in files.items():
            target = staged / relative
            if not target.is_file():
                die(f"{name} {locked['version']} has no {relative}")
            patch_file(target, expected)
        if out.exists():
            shutil.rmtree(out)
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staged), str(out))
    print(f"staged HarmonyOS-patched {name} {locked['version']} in {OUT_DIR}/{name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--archive",
        help="use this local flutter_math_fork archive instead of downloading",
    )
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    for name, files in PATCHES.items():
        stage(name, files, args.archive, root)


if __name__ == "__main__":
    main()
