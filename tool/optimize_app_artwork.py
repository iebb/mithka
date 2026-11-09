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
# Mascot art is flat sticker artwork; ~50 KB keeps it crisp at 1024px.
ICON_TARGET_BYTES = 52 * 1024
ICON_LIMIT_BYTES = 56 * 1024
# Faint paper texture, not colour count, dominates these PNGs. Smoothing it
# away before quantising is tried from gentlest to strongest.
SMOOTHING_LADDER = (
    (3, 64),
    (3, 48),
    (3, 40),
    (3, 32),
    (5, 48),
    (5, 32),
    (5, 24),
)
MIN_PSNR_DB = 36.0


def composer_pngs():
    return [
        path
        for icon in (ROOT / "ios/Runner").glob("*.icon")
        for path in icon.rglob("*.png")
    ]


def size(paths):
    return sum(path.stat().st_size for path in paths)


def uses_glass(icon):
    spec = json.loads((icon / "icon.json").read_text())
    return any(
        layer.get("glass")
        for group in spec.get("groups", [])
        for layer in group.get("layers", [])
    )


def inventory():
    return {
        "launcher_png_bytes": size(ICONS.glob("*.png")),
        "picker_bytes": size(path for path in PICKER.iterdir() if path.is_file()),
        "ios_catalogue_png_bytes": size(NATIVE.rglob("*.png")),
        "ios_composer_png_bytes": size(composer_pngs()),
    }


def check():
    errors = []
    # Xcode bakes every .icon into flattened 1024px light, dark and tinted
    # renditions (~2.2 MB per device), while the same art from an .appiconset
    # compiles to ~0.35 MB. Flat art keeps only its .appiconset.
    for icon in sorted((ROOT / "ios/Runner").glob("*.icon")):
        if not uses_glass(icon) and (NATIVE / f"{icon.stem}.appiconset").is_dir():
            errors.append(
                f"Flat icon duplicates its .appiconset: {icon.relative_to(ROOT)}"
            )
    for path in NATIVE.rglob("*.png"):
        data = path.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            errors.append(f"Invalid native PNG: {path.relative_to(ROOT)}")
            continue
        dimensions = struct.unpack(">II", data[16:24])
        # The three existing clear tinted renditions are 1px placeholders.
        if dimensions not in ((1024, 1024), (1, 1)):
            errors.append(f"Invalid native icon dimensions: {path.relative_to(ROOT)}")
        if len(data) > ICON_LIMIT_BYTES:
            errors.append(f"Native icon exceeds 56 KiB: {path.relative_to(ROOT)}")
    for path in ICONS.glob("*.png"):
        if path.stat().st_size > ICON_LIMIT_BYTES:
            errors.append(f"Launcher icon exceeds 56 KiB: {path.relative_to(ROOT)}")
    for path in PICKER.iterdir():
        if path.suffix != ".webp":
            errors.append(f"Picker must use optimized WebP: {path.relative_to(ROOT)}")
        elif path.stat().st_size > 64 * 1024:
            errors.append(f"Picker exceeds 64 KiB: {path.relative_to(ROOT)}")
    values = inventory()
    if values["picker_bytes"] > 2 * 1024**2:
        errors.append("Picker catalogue exceeds 2 MiB")
    if values["ios_catalogue_png_bytes"] > 6 * 1024**2:
        errors.append("Native iOS icon catalogue exceeds 6 MiB")
    if values["ios_composer_png_bytes"] > 10 * 1024**2:
        errors.append("Native iOS icon layers exceed 10 MiB")
    print(json.dumps(values, indent=2))
    if errors:
        raise SystemExit("\n".join(errors))


def psnr(first, second):
    import math
    from PIL import ImageChops, ImageStat

    # Premultiply so colours hidden under transparent pixels do not count.
    first, second = (image.convert("RGBA").convert("RGBa") for image in (first, second))
    difference = ImageChops.difference(first, second)
    mse = sum(value**2 for value in ImageStat.Stat(difference).rms) / 4
    return math.inf if mse == 0 else 10 * math.log10(255**2 / mse)


def fit_budget(path, directory):
    """Return the gentlest smoothed palette PNG within the icon budget."""
    from PIL import Image, ImageFilter

    with Image.open(path) as image:
        original = image.convert("RGBA")
    best = None
    for radius, colours in SMOOTHING_LADDER:
        source = Path(directory) / f"smooth-{radius}.png"
        if not source.exists():
            original.filter(ImageFilter.MedianFilter(radius)).save(source)
        output = Path(directory) / f"smooth-{radius}-{colours}.png"
        subprocess.run(
            [
                "pngquant",
                "--speed",
                "1",
                "--strip",
                "--nofs",
                "--force",
                "--output",
                str(output),
                str(colours),
                str(source),
            ],
            env={**os.environ, "OMP_NUM_THREADS": "1"},
            check=True,
            capture_output=True,
            timeout=90,
        )
        with Image.open(output) as candidate:
            if psnr(original, candidate) < MIN_PSNR_DB:
                break
        best = output
        if output.stat().st_size <= ICON_TARGET_BYTES:
            break
    return best


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
        if original.stat().st_size <= ICON_TARGET_BYTES:
            return
        with Image.open(original) as image:
            if image.info.get("icc_profile"):
                raise ValueError(f"Convert the color profile explicitly: {original}")
            palette = image.mode == "P"
        with tempfile.TemporaryDirectory(prefix="mithka-png-") as directory:
            output = Path(directory) / "optimized.png"
            result = None
            if not palette:
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
                # 99 preserves quality rather than forcing a poor palette.
                if result.returncode not in (0, 99):
                    raise RuntimeError(result.stderr)
            # Smoothing would blur the pixel-art grid.
            pixel_art = any("pixel" in path.name.lower() for path in group)
            if not pixel_art and (
                result is None
                or result.returncode
                or output.stat().st_size > ICON_TARGET_BYTES
            ):
                output = fit_budget(original, directory) or output
            if output.exists() and output.stat().st_size < original.stat().st_size:
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
