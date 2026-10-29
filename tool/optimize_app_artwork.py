#!/usr/bin/env python3
"""Compress launcher PNGs and create transparent picker WebPs up to 256px.

Writing requires pngquant, cwebp and Pillow. Checking uses only Python's
standard library, so the byte/dimension budgets also run in read-only CI.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / "assets/app_icons"
PICKER = ICONS / "picker"
NATIVE = ROOT / "ios/Runner/Assets.xcassets"


def composer_pngs():
    return [
        path
        for icon in (ROOT / "ios/Runner").glob("*.icon")
        for path in icon.rglob("*.png")
    ]


def size(paths):
    return sum(path.stat().st_size for path in paths)


def inventory():
    return {
        "launcher_png_bytes": size(ICONS.glob("*.png")),
        "picker_bytes": size(path for path in PICKER.iterdir() if path.is_file()),
        "ios_catalogue_png_bytes": size(NATIVE.rglob("*.png")),
        "ios_composer_png_bytes": size(composer_pngs()),
    }


def check():
    errors = []
    for path in NATIVE.rglob("*.png"):
        data = path.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            errors.append(f"Invalid native PNG: {path.relative_to(ROOT)}")
            continue
        dimensions = struct.unpack(">II", data[16:24])
        # The three existing clear tinted renditions are 1px placeholders.
        if dimensions not in ((1024, 1024), (1, 1)):
            errors.append(f"Invalid native icon dimensions: {path.relative_to(ROOT)}")
        if len(data) > 384 * 1024:
            errors.append(f"Native icon exceeds 384 KiB: {path.relative_to(ROOT)}")
    for path in PICKER.iterdir():
        if path.suffix != ".webp":
            errors.append(f"Picker must use optimized WebP: {path.relative_to(ROOT)}")
        elif path.stat().st_size > 64 * 1024:
            errors.append(f"Picker exceeds 64 KiB: {path.relative_to(ROOT)}")
    values = inventory()
    if values["picker_bytes"] > 2 * 1024**2:
        errors.append("Picker catalogue exceeds 2 MiB")
    if values["ios_catalogue_png_bytes"] > 22 * 1024**2:
        errors.append("Native iOS icon catalogue exceeds 22 MiB")
    if values["ios_composer_png_bytes"] > 10 * 1024**2:
        errors.append("Native iOS icon layers exceed 10 MiB")
    print(json.dumps(values, indent=2))
    if errors:
        raise SystemExit("\n".join(errors))


def optimize():
    from PIL import Image

    for program in ("pngquant", "cwebp"):
        if shutil.which(program) is None:
            raise SystemExit(f"Missing artwork optimizer: {program}")
    before = inventory()
    native_paths = [*ICONS.glob("*.png"), *NATIVE.rglob("*.png")]
    native_paths += composer_pngs()
    native_paths += [ROOT / "assets/app_icon.png", ROOT / "assets/penguin.png"]
    groups = {}
    for path in native_paths:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        groups.setdefault(digest, []).append(path)

    def compress(group):
        original = group[0]
        with Image.open(original) as image:
            if image.mode == "P" or original.stat().st_size < 1024:
                return
            if image.info.get("icc_profile"):
                raise ValueError(f"Convert the color profile explicitly: {original}")
        with tempfile.TemporaryDirectory(prefix="mithka-png-") as directory:
            output = Path(directory) / "optimized.png"
            result = subprocess.run(
                [
                    "pngquant",
                    "--quality=80-95",
                    "--speed",
                    "1",
                    "--strip",
                    "--floyd=0.35",
                    "--output",
                    str(output),
                    str(original),
                ],
                env={**os.environ, "OMP_NUM_THREADS": "1"},
                capture_output=True,
                text=True,
                timeout=90,
            )
            if (
                result.returncode == 99
            ):  # Preserve quality rather than forcing a poor palette.
                return
            if result.returncode:
                raise RuntimeError(result.stderr)
            if output.stat().st_size < original.stat().st_size:
                data = output.read_bytes()
                for path in group:
                    path.write_bytes(data)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(compress, groups.values()))

    for source in sorted(PICKER.glob("*.png")):
        output = source.with_suffix(".webp")
        with Image.open(source) as image:
            resampling = (
                Image.Resampling.NEAREST
                if "pixel" in source.stem
                else Image.Resampling.LANCZOS
            )
            image.thumbnail((256, 256), resampling)
            if "pixel" in source.stem:
                # Keep the pixel-art grid and every alpha value exact.
                image.save(
                    output,
                    "WEBP",
                    lossless=True,
                    method=6,
                )
            else:
                subprocess.run(
                    [
                        "cwebp",
                        "-quiet",
                        "-resize",
                        str(image.width),
                        str(image.height),
                        "-q",
                        "85",
                        "-alpha_q",
                        "100",
                        "-m",
                        "6",
                        "-sharp_yuv",
                        str(source),
                        "-o",
                        str(output),
                    ],
                    check=True,
                    timeout=60,
                )
        with Image.open(output) as image:
            assert max(image.size) <= 256 and image.mode == "RGBA"
        source.unlink()
    print(json.dumps({"before": before, "after": inventory()}, indent=2))
    check()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write", action="store_true", help="Optimize checked-in artwork"
    )
    parser.add_argument(
        "--check", action="store_true", help="Check packaging budgets only"
    )
    arguments = parser.parse_args()
    if arguments.write == arguments.check:
        parser.error("Choose exactly one of --write or --check")
    optimize() if arguments.write else check()
