#!/usr/bin/env python3
"""Remove files a desktop release bundle never uses, and strip native symbols.

Flutter copies every plugin's bundled libraries into the desktop bundle, and
several of them are dead weight for Mithka:

* MDK's RED (R3D), Blackmagic RAW (BRAW) and NVIDIA JPEG 2000 decoder plugins.
  MDK loads them on demand for professional camera formats and falls back to
  FFmpeg when they are absent, exactly like the Rockchip plugin the AppImage
  already omits.
* package:jni's ``dartjni`` library. Only sentry_flutter's Android binding uses
  JNI, and on Linux the library links ``libjvm.so``, so linuxdeploy bundles a
  19 MB JVM into the AppImage for it.
* Windows import libraries and linker by-products, which the installer already
  excludes but the portable zip kept.

Linux plugins and the pinned TDLib library are also shipped with their full
symbol tables (TDLib alone carries 12 MB), so unstripped ELF files are stripped
with ``--strip-unneeded``, which keeps every dynamic symbol FFI and the dynamic
loader resolve. On macOS ``flutter build macos`` does not post-process the
runner executable the way an Xcode archive does, so its local symbols are
stripped; the caller re-signs the bundle afterwards.
"""

from __future__ import annotations

import argparse
import shutil
import struct
import subprocess
import sys
from pathlib import Path

REMOVED = {
    "linux": (
        "lib/libmdk-r3d.so",
        "lib/libmdk-braw.so",
        "lib/libdartjni.so",
    ),
    "macos": (
        "Contents/Frameworks/mdk.framework/Versions/A/libmdk-r3d.dylib",
        "Contents/Frameworks/mdk.framework/Versions/A/libmdk-braw.dylib",
    ),
    "windows": (
        "mdk-r3d.dll",
        "mdk-braw.dll",
        "mdk-nvjp2k.dll",
        "dartjni.dll",
    ),
}
# Matches the installer's Excludes list in windows/installer/mithka.iss.
WINDOWS_BUILD_BY_PRODUCTS = ("*.exp", "*.ilk", "*.lib", "*.pdb")


class PruneError(Exception):
    pass


def elf_has_symtab(path: Path) -> bool:
    """Whether ``path`` is an ELF file that still carries a ``.symtab``."""
    with path.open("rb") as stream:
        ident = stream.read(16)
        if len(ident) < 16 or ident[:4] != b"\x7fELF" or ident[4] != 2:
            return False
        endian = "<" if ident[5] == 1 else ">"
        header = stream.read(48)
        if len(header) < 48:
            return False
        section_offset = struct.unpack_from(endian + "Q", header, 24)[0]
        entry_size, count, names_index = struct.unpack_from(endian + "HHH", header, 42)
        if not section_offset or not count or entry_size < 64:
            return False
        stream.seek(section_offset)
        table = stream.read(entry_size * count)
        if len(table) < entry_size * count or names_index >= count:
            return False

        def section(index: int) -> tuple[int, int, int, int]:
            name, kind, _, _, offset, size = struct.unpack_from(
                endian + "IIQQQQ", table, index * entry_size
            )
            return name, kind, offset, size

        _, _, names_offset, names_size = section(names_index)
        stream.seek(names_offset)
        names = stream.read(names_size)
        for index in range(count):
            name, kind, _, _ = section(index)
            # SHT_SYMTAB; the dynamic table is SHT_DYNSYM and always stays.
            if kind == 2 and names[name : names.index(b"\0", name)] == b".symtab":
                return True
    return False


def remove(bundle: Path, platform: str) -> list[tuple[Path, int]]:
    removed = []
    candidates = [bundle / name for name in REMOVED[platform]]
    if platform == "windows":
        for pattern in WINDOWS_BUILD_BY_PRODUCTS:
            candidates.extend(sorted(bundle.rglob(pattern)))
    for path in candidates:
        if path.is_file() and not path.is_symlink():
            removed.append((path, path.stat().st_size))
            path.unlink()
    return removed


def strip(bundle: Path, platform: str, tool: str | None) -> list[tuple[Path, int]]:
    if platform == "linux":
        files = [bundle / "mithka", *sorted((bundle / "lib").iterdir())]
        targets = [
            path
            for path in files
            if path.is_file() and not path.is_symlink() and elf_has_symtab(path)
        ]
        arguments = ["--strip-unneeded"]
    elif platform == "macos":
        executable = bundle / "Contents/MacOS/Mithka"
        if not executable.is_file():
            raise PruneError(f"missing app executable: {executable}")
        targets = [executable]
        # Local symbols and debug notes only; exported symbols stay resolvable.
        arguments = ["-x", "-S"]
    else:
        return []

    program = tool or shutil.which("strip")
    if not program:
        raise PruneError("strip is required to prune a desktop bundle")
    stripped = []
    for path in targets:
        before = path.stat().st_size
        result = subprocess.run(
            [program, *arguments, str(path)], capture_output=True, text=True
        )
        if result.returncode:
            raise PruneError(f"strip failed for {path}: {result.stderr.strip()}")
        stripped.append((path, before - path.stat().st_size))
    return stripped


def validate_bundle(bundle: Path, platform: str) -> None:
    marker = {
        "linux": bundle / "lib/libapp.so",
        "macos": bundle / "Contents/Info.plist",
        "windows": bundle / "data/app.so",
    }[platform]
    if not marker.is_file():
        raise PruneError(
            f"{bundle} is not a {platform} release bundle ({marker} is missing)"
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("platform", choices=sorted(REMOVED))
    parser.add_argument("bundle", type=Path)
    parser.add_argument(
        "--strip-tool", help="strip executable (default: strip on PATH)"
    )
    args = parser.parse_args(argv)

    try:
        validate_bundle(args.bundle, args.platform)
        removed = remove(args.bundle, args.platform)
        stripped = strip(args.bundle, args.platform, args.strip_tool)
    except (OSError, PruneError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    for path, size in removed:
        print(f"removed  {size / 1048576:7.2f} MB  {path.relative_to(args.bundle)}")
    for path, size in stripped:
        print(f"stripped {size / 1048576:7.2f} MB  {path.relative_to(args.bundle)}")
    total = sum(size for _, size in removed) + sum(size for _, size in stripped)
    print(f"Pruned {total / 1048576:.1f} MB from the {args.platform} bundle")
    return 0


if __name__ == "__main__":
    sys.exit(main())
