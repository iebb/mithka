import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "prune_desktop_bundle", ROOT / "scripts/prune-desktop-bundle.py"
)
prune = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prune)


def elf(symtab):
    """A minimal little-endian ELF64 image with section headers."""
    names = b"\0.shstrtab\0.symtab\0"
    sections = [(0, 0, 0, 0), (1, 3, 64, len(names))]
    if symtab:
        sections.append((11, 2, 0, 0))
    header_offset = 64 + len(names)
    ident = b"\x7fELF" + bytes([2, 1, 1]) + bytes(9)
    # e_type .. e_shstrndx for an x86-64 shared object without program headers.
    fields = (3, 62, 1, 0, 0, header_offset, 0, 64, 0, 0, 64, len(sections), 1)
    header = struct.pack("<HHIQQQIHHHHHH", *fields)
    table = b"".join(
        struct.pack("<IIQQQQIIQQ", name, kind, 0, 0, offset, size, 0, 0, 1, 0)
        for name, kind, offset, size in sections
    )
    return ident + header + names + table


class PruneDesktopBundleTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        # Records each invocation instead of rewriting the fixture binaries.
        self.calls = self.root / "strip-calls.jsonl"
        self.strip = self.root / "fake-strip"
        self.strip.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "with open(os.environ['STRIP_CALLS'], 'a') as calls:\n"
            "    calls.write(json.dumps(sys.argv[1:]) + '\\n')\n"
        )
        self.strip.chmod(0o755)
        os.environ["STRIP_CALLS"] = str(self.calls)
        self.addCleanup(os.environ.pop, "STRIP_CALLS", None)

    def write(self, path, data=b"x"):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def run_prune(self, platform, bundle):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            status = prune.main(
                [platform, str(bundle), "--strip-tool", str(self.strip)]
            )
        return status, output.getvalue()

    def stripped(self, bundle):
        if not self.calls.exists():
            return []
        return [
            (call[:-1], Path(call[-1]).relative_to(bundle).as_posix())
            for call in map(json.loads, self.calls.read_text().splitlines())
        ]

    def test_symtab_detection_reads_section_types(self):
        self.assertTrue(prune.elf_has_symtab(self.write(self.root / "a", elf(True))))
        self.assertFalse(prune.elf_has_symtab(self.write(self.root / "b", elf(False))))
        self.assertFalse(prune.elf_has_symtab(self.write(self.root / "c", b"MZ")))

    def test_linux_drops_unused_plugins_and_strips_only_unstripped_elf(self):
        bundle = self.root / "bundle"
        self.write(bundle / "mithka", elf(False))
        self.write(bundle / "lib/libapp.so", elf(False))
        self.write(bundle / "lib/libtdjson.so", elf(True))
        self.write(bundle / "lib/libsentry.so", elf(True))
        self.write(bundle / "lib/libmdk.so.0", elf(False))
        for name in ("libmdk-r3d.so", "libmdk-braw.so", "libdartjni.so"):
            self.write(bundle / "lib" / name, elf(True))
        self.write(bundle / "data/icudtl.dat")

        status, output = self.run_prune("linux", bundle)

        self.assertEqual(status, 0, output)
        remaining = sorted(path.name for path in (bundle / "lib").iterdir())
        self.assertEqual(
            remaining, ["libapp.so", "libmdk.so.0", "libsentry.so", "libtdjson.so"]
        )
        self.assertEqual(
            self.stripped(bundle),
            [
                (["--strip-unneeded"], "lib/libsentry.so"),
                (["--strip-unneeded"], "lib/libtdjson.so"),
            ],
        )

    def test_macos_drops_raw_decoders_and_strips_the_runner_locals(self):
        app = self.root / "Mithka.app"
        mdk = app / "Contents/Frameworks/mdk.framework/Versions/A"
        self.write(app / "Contents/Info.plist")
        self.write(app / "Contents/MacOS/Mithka")
        for name in (
            "mdk",
            "libffmpeg.9.dylib",
            "libmdk-r3d.dylib",
            "libmdk-braw.dylib",
        ):
            self.write(mdk / name)

        status, output = self.run_prune("macos", app)

        self.assertEqual(status, 0, output)
        self.assertEqual(
            sorted(p.name for p in mdk.iterdir()), ["libffmpeg.9.dylib", "mdk"]
        )
        self.assertEqual(self.stripped(app), [(["-x", "-S"], "Contents/MacOS/Mithka")])

    def test_windows_matches_the_installer_exclusions(self):
        bundle = self.root / "Release"
        self.write(bundle / "data/app.so")
        kept = ["mithka.exe", "mdk.dll", "ffmpeg-9.dll", "libass.dll", "sentry.dll"]
        removed = [
            "mdk-r3d.dll",
            "mdk-braw.dll",
            "mdk-nvjp2k.dll",
            "dartjni.dll",
            "firebase_core_plugin.lib",
            "mithka.lib",
            "mithka.exp",
        ]
        for name in kept + removed:
            self.write(bundle / name)
        self.write(bundle / "data/debug/plugin.pdb")

        status, output = self.run_prune("windows", bundle)

        self.assertEqual(status, 0, output)
        self.assertEqual(
            sorted(p.name for p in bundle.iterdir() if p.is_file()), sorted(kept)
        )
        self.assertFalse((bundle / "data/debug/plugin.pdb").exists())
        self.assertEqual(self.stripped(bundle), [])

    def test_rejects_a_directory_that_is_not_the_requested_bundle(self):
        bundle = self.root / "Release"
        self.write(bundle / "data/app.so")
        self.write(bundle / "mdk-r3d.dll")

        status, output = self.run_prune("linux", bundle)

        self.assertEqual(status, 1)
        self.assertIn("is not a linux release bundle", output)
        self.assertTrue((bundle / "mdk-r3d.dll").exists())

    def test_a_second_run_is_a_no_op(self):
        bundle = self.root / "Release"
        self.write(bundle / "data/app.so")
        self.write(bundle / "dartjni.dll")
        self.assertEqual(self.run_prune("windows", bundle)[0], 0)

        status, output = self.run_prune("windows", bundle)

        self.assertEqual(status, 0, output)
        self.assertIn("Pruned 0.0 MB from the windows bundle", output)


if __name__ == "__main__":
    unittest.main()
