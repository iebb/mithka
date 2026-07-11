#!/usr/bin/env python3
"""Fix mithka non-default adaptive icon dimensions.

Issue: non-default icons (white, blue, purple, pixel) have foreground and
background layers at legacy icon sizes (48dp) instead of adaptive icon sizes
(108dp). When Android scales them up to fill the 108dp canvas, the content
exceeds the 72dp safe zone and gets clipped by the launcher mask.

Fix: resize all non-default foreground/background/monochrome layers to the
correct adaptive icon dimensions, scaling content to fit within the safe zone.
"""

from PIL import Image
import os
import sys

BASE = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')

DENSITIES = {
    'mdpi': 1,
    'hdpi': 1.5,
    'xhdpi': 2,
    'xxhdpi': 3,
    'xxxhdpi': 4,
}

VARIANTS = ['white', 'blue', 'purple', 'pixel']
LAYERS = ['foreground', 'background', 'monochrome']

ADAPTIVE_DP = 108
SAFE_ZONE_DP = 72
# Target content to occupy ~58% of canvas (well within 66.7% safe zone)
TARGET_CONTENT_PCT = 0.58


def fix_icon(path: str, is_background: bool) -> bool:
    """Fix a single icon layer image. Returns True if modified."""
    if not os.path.exists(path):
        return False

    img = Image.open(path)
    density_name = os.path.basename(os.path.dirname(path)).replace('mipmap-', '').replace('mipmap-anydpi-', '')
    factor = DENSITIES.get(density_name)
    if factor is None:
        return False

    correct_size = int(ADAPTIVE_DP * factor)

    if img.size == (correct_size, correct_size):
        return False  # Already correct

    if is_background:
        # Background: just scale to fill the canvas
        new_img = img.resize((correct_size, correct_size), Image.LANCZOS)
    else:
        # Foreground/monochrome: extract content, scale to fit in safe zone, center
        bbox = img.getbbox()
        if bbox is None:
            return False  # Fully transparent, nothing to do

        content = img.crop(bbox)
        cw, ch = content.size

        # Target: content should occupy TARGET_CONTENT_PCT of the new canvas
        target_content_size = correct_size * TARGET_CONTENT_PCT
        scale = min(target_content_size / cw, target_content_size / ch)
        new_cw = int(cw * scale)
        new_ch = int(ch * scale)
        scaled_content = content.resize((new_cw, new_ch), Image.LANCZOS)

        # Center in transparent canvas
        new_img = Image.new('RGBA', (correct_size, correct_size), (0, 0, 0, 0))
        offset_x = (correct_size - new_cw) // 2
        offset_y = (correct_size - new_ch) // 2
        new_img.paste(scaled_content, (offset_x, offset_y), scaled_content)

    new_img.save(path, 'PNG')
    return True


def main():
    fixed = 0
    for variant in VARIANTS:
        for density in DENSITIES:
            mipmap_dir = os.path.join(BASE, f'mipmap-{density}')
            for layer in LAYERS:
                path = os.path.join(mipmap_dir, f'ic_launcher_{variant}_{layer}.png')
                is_bg = (layer == 'background')
                if fix_icon(path, is_bg):
                    fixed += 1
                    print(f'  FIXED: {path}')

    print(f'\nDone. Fixed {fixed} icon layers.')


if __name__ == '__main__':
    main()
