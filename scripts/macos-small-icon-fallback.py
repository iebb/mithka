#!/usr/bin/env python3
"""Keep legacy 16/32-point ICNS fallbacks without replacing Liquid Glass assets.

Icon Composer owns Assets.car, including the system-rendered icon on modern
macOS. Only the standalone ICNS representations used by legacy consumers are
changed, after asset compilation and before signing. Larger representations
from Icon Composer are retained byte for byte.
"""

import argparse
import struct
from pathlib import Path


SMALL_TYPES = {b"ic04", b"ic05", b"ic06", b"icp4", b"icp5", b"icp6", b"ic11", b"ic12"}
FALLBACKS = ((b"icp4", 16), (b"ic11", 32), (b"icp5", 32), (b"ic12", 64))


def read_chunks(data):
    if len(data) < 8 or struct.unpack_from(">4sI", data) != (b"icns", len(data)):
        raise ValueError("invalid ICNS header")
    offset = 8
    chunks = []
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("truncated ICNS chunk")
        kind, length = struct.unpack_from(">4sI", data, offset)
        if length < 8 or offset + length > len(data):
            raise ValueError("invalid ICNS chunk length")
        chunks.append((kind, data[offset : offset + length]))
        offset += length
    return chunks


def legacy_chunks(source):
    chunks = []
    for kind, size in FALLBACKS:
        png = (source / f"app_icon_{size}.png").read_bytes()
        if (
            png[:16] != b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
            or struct.unpack_from(">II", png, 16) != (size, size)
        ):
            raise ValueError(f"expected a {size}-pixel PNG")
        chunks.append((kind, struct.pack(">4sI", kind, len(png) + 8) + png))
    return chunks


def update_icon(data, source):
    retained = [(kind, chunk) for kind, chunk in read_chunks(data) if kind not in SMALL_TYPES]
    if not retained:
        raise ValueError("Icon Composer's larger representations must be present")
    payload = b"".join(chunk for _, chunk in retained + legacy_chunks(source))
    return struct.pack(">4sI", b"icns", len(payload) + 8) + payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("icon", type=Path)
    parser.add_argument("source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    original = args.icon.read_bytes()
    updated = update_icon(original, args.source)
    if args.check:
        if original != updated:
            raise SystemExit("legacy small-icon fallbacks are missing or stale")
    elif original != updated:
        args.icon.write_bytes(updated)
    print("Verified legacy 16/32-point fallbacks; larger Liquid Glass assets retained")


if __name__ == "__main__":
    main()
