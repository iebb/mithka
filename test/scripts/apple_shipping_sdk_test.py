"""Credential-free shipping SDK regressions; run with python3 -m unittest discover -s test/scripts -p '*_test.py'."""

import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/apple_shipping_sdk.py"


class AppleShippingSdkTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apps = self.root / "Applications with spaces"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.apps.mkdir()
        self.provenance = self.root / "selection.json"
        self.report = self.root / "verification.json"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", GITHUB_ENV=str(self.root / "github-env"), GITHUB_SHA="a" * 40, XCODE_XCCONFIG_FILE="injected file must survive")
        self.env.pop("DEVELOPER_DIR", None)
        # All commands assert the platform's injected xcconfig survives intact.
        mock = '''#!/usr/bin/env python3
import json, os, pathlib, sys
assert os.environ["XCODE_XCCONFIG_FILE"] == "injected file must survive"
if pathlib.Path(sys.argv[0]).name == "xcode-select":
    sys.exit(1)
data = json.loads((pathlib.Path(os.environ["DEVELOPER_DIR"]) / "mock.json").read_text())
if pathlib.Path(sys.argv[0]).name == "xcodebuild":
    print("Xcode " + data["xcode"] + "\\nBuild version " + data["build"])
elif sys.argv[-1] == "--show-sdk-version":
    print(data["sdk"])
else:
    print(data["sdk_build"])
'''
        for name in ("xcode-select", "xcodebuild", "xcrun"):
            path = self.bin / name
            path.write_text(mock)
            path.chmod(0o755)

    def candidate(self, name="Xcode 27.1 RC.app", xcode="27.1", sdk="27.1", build="18B42", sdk_build="24B42"):
        path = self.apps / name / "Contents/Developer"
        path.mkdir(parents=True)
        (path / "mock.json").write_text(json.dumps(dict(xcode=xcode, sdk=sdk, build=build, sdk_build=sdk_build)))
        return path

    def command(self, *arguments, success=True):
        result = subprocess.run([sys.executable, str(SCRIPT), *arguments], env=self.env, text=True, capture_output=True)
        if success:
            self.assertEqual(0, result.returncode, result.stderr)
        else:
            self.assertNotEqual(0, result.returncode, result.stdout)
        return result

    def select(self, success=True):
        result = self.command("select", "--applications", str(self.apps), "--provenance", str(self.provenance), success=success)
        data = json.loads(self.provenance.read_text())
        if success:
            self.env["DEVELOPER_DIR"] = data["toolchain"]["developer_dir"]
            self.assertEqual("a" * 40, data["source_sha"])
            self.assertTrue(data["xccconfig_injected"])
            self.assertIn(f"DEVELOPER_DIR={self.env['DEVELOPER_DIR']}\n", (self.root / "github-env").read_text())
        return result, data

    def info(self):
        return dict(DTSDKName="iphoneos27.1", DTSDKBuild="24B42", DTXcode="2710", DTXcodeBuild="18B42", DTPlatformName="iphoneos", DTPlatformVersion="27.1")

    def artifact(self, info=None):
        archive = self.root / "Shipping app.xcarchive"
        app = archive / "Products/Applications/Runner.app"
        app.mkdir(parents=True)
        (app / "Info.plist").write_bytes(plistlib.dumps(info or self.info(), fmt=plistlib.FMT_BINARY))
        return archive

    def verify(self, artifact, success=True):
        return self.command("verify", "--provenance", str(self.provenance), "--artifact", str(artifact), "--report", str(self.report), success=success)

    def test_old_xcode_and_wrong_sdk_fail_closed(self):
        for xcode, sdk in (("26.4", "26.4"), ("27.0", "27.0"), ("27.1", "27.0"), ("27.0", "27.1")):
            with self.subTest(xcode=xcode, sdk=sdk):
                self.candidate(name=f"Xcode_{xcode}_{sdk}.app", xcode=xcode, sdk=sdk)
        result, data = self.select(success=False)
        self.assertEqual("blocked", data["status"])
        self.assertEqual(4, len(data["rejected_candidates"]))
        self.assertIn("RELEASE BLOCKER", result.stderr)
        self.assertFalse((self.root / "github-env").exists())

    def test_unavailable_fails_closed(self):
        self.assertIn("no older-SDK fallback", self.select(success=False)[0].stderr)

    def test_rc_names_and_spaces_use_actual_version_not_filename(self):
        expected = self.candidate(name="Xcode_99 misleading 27.1 RC.app")
        self.candidate(name="Xcode_100.app", xcode="26.4", sdk="26.4")
        _, data = self.select()
        self.assertEqual(str(expected.resolve()), data["toolchain"]["developer_dir"])
        self.verify(self.artifact())

    def test_numeric_patch_sort_within_approved_series(self):
        self.candidate(xcode="27.1.9", sdk="27.1")
        expected = self.candidate(name="Xcode patched RC.app", xcode="27.1.10", sdk="27.1")
        self.assertEqual(str(expected.resolve()), self.select()[1]["toolchain"]["developer_dir"])

    def test_numeric_only_newer_beta_does_not_outrank_shipping_rc(self):
        expected = self.candidate(name="Xcode_27.1_Release_Candidate.app", build="27A9275")
        self.candidate(name="Xcode_27.2_beta_2.app", xcode="27.2", sdk="27.2", build="27B5028f")
        self.candidate(name="Xcode misleading alias.app", xcode="27.1", sdk="27.2")
        _, data = self.select()
        self.assertEqual(str(expected.resolve()), data["toolchain"]["developer_dir"])
        self.assertEqual(2, len(data["rejected_candidates"]))
        self.assertEqual("27.1", data["approved_shipping_series"])

    def test_newer_unapproved_series_alone_fails_closed(self):
        self.candidate(name="Xcode_27.2.app", xcode="27.2", sdk="27.2", build="27B5028f")
        self.assertIn("outside approved shipping series", self.select(success=False)[0].stderr)

    def test_injected_developer_outside_applications(self):
        expected = self.candidate().rename(self.root / "Injected RC Developer")
        self.env["DEVELOPER_DIR"] = str(expected.resolve())
        self.assertEqual(str(expected.resolve()), self.select()[1]["toolchain"]["developer_dir"])

    def test_explicit_beta_output_is_not_shipping_rc(self):
        self.candidate(xcode="27.1 beta 2")
        self.assertIn("Beta/preview", self.select(success=False)[0].stderr)

    def test_archive_fields_all_required_and_match_actual_toolchain(self):
        self.candidate()
        self.select()
        archive = self.artifact()
        plist = archive / "Products/Applications/Runner.app/Info.plist"
        for key, wrong in (("DTSDKName", "iphoneos27.0"), ("DTSDKName", "iphonesimulator27.1"), ("DTSDKBuild", "old"), ("DTXcode", "2700"), ("DTXcodeBuild", "old"), ("DTPlatformName", "iphonesimulator"), ("DTPlatformVersion", "27.0")):
            with self.subTest(key=key, wrong=wrong):
                info = self.info()
                info[key] = wrong
                plist.write_bytes(plistlib.dumps(info))
                self.verify(archive, success=False)
        for key in self.info():
            with self.subTest(missing=key):
                info = self.info()
                del info[key]
                plist.write_bytes(plistlib.dumps(info))
                self.verify(archive, success=False)
        self.assertFalse(self.report.exists())

    def test_exported_ipa_is_checked_and_hashed(self):
        self.candidate()
        self.select()
        ipa = self.root / "Shipping app.ipa"
        with zipfile.ZipFile(ipa, "w") as archive:
            archive.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(self.info()))
        self.verify(ipa)
        data = json.loads(self.report.read_text())
        self.assertEqual(64, len(data["artifact_sha256"]))
        self.assertEqual("verified", data["status"])

    def test_old_embedded_extension_blocks_ipa(self):
        self.candidate()
        self.select()
        ipa = self.root / "App.ipa"
        wrong = self.info()
        wrong["DTSDKName"] = "iphoneos26.0"
        with zipfile.ZipFile(ipa, "w") as archive:
            archive.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(self.info()))
            archive.writestr("Payload/Runner.app/PlugIns/Share.appex/Info.plist", plistlib.dumps(wrong))
        self.assertIn("Share.appex", self.verify(ipa, success=False).stderr)

    def test_selection_or_environment_drift_blocks_verification(self):
        candidate = self.candidate()
        self.select()
        artifact = self.artifact()
        self.env["DEVELOPER_DIR"] = str(self.root)
        self.assertIn("DEVELOPER_DIR changed", self.verify(artifact, success=False).stderr)
        self.env["DEVELOPER_DIR"] = str(candidate)
        data = json.loads((candidate / "mock.json").read_text())
        data["build"] = "different"
        (candidate / "mock.json").write_text(json.dumps(data))
        self.assertIn("changed since selection", self.verify(artifact, success=False).stderr)

    def test_workflow_guards_precede_upload_and_credentials(self):
        workflow = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
        self.assertIn("runs-on: xcode-27", workflow)
        self.assertNotIn("Select Xcode 26", workflow)
        self.assertLess(workflow.index("apple_shipping_sdk.py select"), workflow.index("Prepare App Store Connect credential"))
        self.assertLess(workflow.index('--artifact "$ARCHIVE_PATH"'), workflow.index("xcodebuild -exportArchive"))
        self.assertLess(workflow.index('--artifact "$ipa"'), workflow.index("xcrun altool --upload-package"))
        self.assertIn("Retain shipping SDK provenance", workflow)
        quality = (ROOT / ".github/workflows/quality.yml").read_text()
        self.assertIn("python3 -m unittest discover -s test/scripts -p 'apple_shipping_sdk_test.py'", quality)
        pr = (ROOT / ".github/workflows/apple-pr.yml").read_text()
        self.assertIn("runs-on: xcode-27", pr)
        self.assertIn("apple_shipping_sdk.py select", pr)
        self.assertIn("test_shipping_device_sdk", pr)


if __name__ == "__main__":
    unittest.main()
