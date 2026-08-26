#!/usr/bin/env python3
"""Drop a package's Windows plugin declaration from the resolved package.

Flutter decides which native plugins a Windows build links by reading every
resolved package's ``pubspec.yaml``; there is no per-architecture switch. A
package whose Windows implementation ships no ARM64 binaries therefore cannot
be excluded from an ARM64 build any other way.

This edits the resolved copy under the pub cache, so it only affects the
checkout it runs in, and it fails loudly rather than silently doing nothing if
the declaration it expects has moved.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

PACKAGE_CONFIG = Path(".dart_tool/package_config.json")
PLATFORM_KEY = re.compile(r"^(\s*)platforms:\s*$")
WINDOWS_KEY = re.compile(r"^(\s*)windows:\s*$")


class DropError(Exception):
    pass


DRIVE_LETTER = re.compile(r"^/[A-Za-z]:[/\\]")


def package_root(root_uri: str) -> Path:
    """The directory a package_config.json ``rootUri`` points at.

    A Windows file URI is ``file:///C:/...``, and its path keeps a leading
    slash in front of the drive letter that has to come off before it names
    anything. A relative rootUri is relative to ``.dart_tool/``.
    """
    parsed = urlparse(root_uri)
    path = unquote(parsed.path)
    if parsed.scheme == "file":
        if DRIVE_LETTER.match(path):
            path = path[1:]
        return Path(path)
    return PACKAGE_CONFIG.parent / path


def resolve_package(name: str) -> Path:
    if not PACKAGE_CONFIG.is_file():
        raise DropError(f"{PACKAGE_CONFIG} is missing; run `flutter pub get` first")
    config = json.loads(PACKAGE_CONFIG.read_text(encoding="utf-8"))
    for package in config.get("packages", []):
        if package.get("name") == name:
            return package_root(package.get("rootUri", "")).resolve()
    raise DropError(f"{name} is not a resolved dependency")


def strip_windows_platform(text: str) -> str:
    """Remove the ``windows:`` entry from the plugin's ``platforms:`` map."""
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    index = 0
    removed = 0
    platform_indent: int | None = None

    while index < len(lines):
        line = lines[index]
        platform_match = PLATFORM_KEY.match(line)
        if platform_match:
            platform_indent = len(platform_match.group(1))
            out.append(line)
            index += 1
            continue

        windows_match = WINDOWS_KEY.match(line)
        if windows_match and platform_indent is not None:
            indent = len(windows_match.group(1))
            if indent <= platform_indent:
                # A sibling of platforms:, not one of its entries.
                platform_indent = None
                out.append(line)
                index += 1
                continue
            index += 1
            # The entry owns every following line indented deeper than its key.
            while index < len(lines):
                following = lines[index]
                if following.strip() and len(following) - len(
                    following.lstrip()
                ) <= indent:
                    break
                index += 1
            removed += 1
            continue

        if line.strip() and platform_indent is not None:
            if len(line) - len(line.lstrip()) <= platform_indent:
                platform_indent = None
        out.append(line)
        index += 1

    if removed != 1:
        raise DropError(
            f"expected exactly one windows: plugin entry, removed {removed}"
        )
    return "".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", help="package whose Windows plugin to drop")
    parser.add_argument(
        "--reason",
        default="",
        help="why the plugin is being dropped, echoed into the build log",
    )
    args = parser.parse_args()

    try:
        root = resolve_package(args.package)
        pubspec = root / "pubspec.yaml"
        if not pubspec.is_file():
            raise DropError(f"{pubspec} is missing")
        original = pubspec.read_text(encoding="utf-8")
        pubspec.write_text(strip_windows_platform(original), encoding="utf-8")
    except DropError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if args.reason:
        print(args.reason)
    print(f"Dropped the Windows plugin declaration from {args.package} ({root})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
