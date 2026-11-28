import importlib.util
import struct
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "macos_small_icon_fallback", ROOT / "scripts/macos-small-icon-fallback.py"
)
icons = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(icons)
SOURCE = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"


def chunk(kind, content):
    return struct.pack(">4sI", kind, len(content) + 8) + content


def icns(*chunks):
    payload = b"".join(chunks)
    return struct.pack(">4sI", b"icns", len(payload) + 8) + payload


class SmallIconFallbackTest(unittest.TestCase):
    def test_keeps_large_representations_and_only_replaces_small_ones(self):
        large = chunk(b"ic13", b"large-icon-composer-payload")
        original = icns(chunk(b"ic04", b"old-small-payload"), large)
        updated = icons.update_icon(original, SOURCE)
        chunks = dict(icons.read_chunks(updated))
        self.assertEqual(chunks.pop(b"ic13"), large)
        self.assertEqual(chunks, dict(icons.legacy_chunks(SOURCE)))
        self.assertEqual(icons.update_icon(updated, SOURCE), updated)

    def test_rejects_missing_large_icon_instead_of_shipping_only_flat_art(self):
        with self.assertRaises(ValueError):
            icons.update_icon(icns(chunk(b"icp4", b"small")), SOURCE)

    def test_rejects_malformed_compiler_output(self):
        for invalid in (b"", icns() + b"x", icns(b"ic13\x00\x00\x00\x00")):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                icons.update_icon(invalid, SOURCE)

    def test_rejects_wrong_size_source(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "app_icon_16.png").write_bytes(
                (SOURCE / "app_icon_32.png").read_bytes()
            )
            with self.assertRaises(ValueError):
                icons.update_icon(icns(chunk(b"ic13", b"large")), source)


if __name__ == "__main__":
    unittest.main()
