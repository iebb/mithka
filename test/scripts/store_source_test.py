import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHA = "a" * 40


class StoreSourceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        for name in ["verify-store-source.sh", "apple_marketing_version.sh"]:
            shutil.copyfile(ROOT / "scripts" / name, self.root / "scripts" / name)
        (self.root / "pubspec.yaml").write_text("name: mithka\nversion: 1.8.8+296\n")
        self.env = dict(
            os.environ,
            GITHUB_REPOSITORY="iebb/mithka",
            GITHUB_REF="refs/heads/master",
            GITHUB_SHA=SHA,
            GITHUB_EVENT_NAME="workflow_dispatch",
            EXPECTED_SOURCE_COMMIT="",
        )

    def run_guard(self):
        return subprocess.run(
            ["bash", "scripts/verify-store-source.sh"],
            cwd=self.root,
            env=self.env,
            capture_output=True,
            text=True,
        ).returncode

    def test_normal_push_keeps_existing_behavior(self):
        self.env.update(GITHUB_REF="refs/heads/nightly", GITHUB_EVENT_NAME="push")
        self.assertEqual(self.run_guard(), 0)

    def test_expected_source_matches(self):
        self.env["EXPECTED_SOURCE_COMMIT"] = SHA
        self.assertEqual(self.run_guard(), 0)

    def test_changed_or_invalid_source_is_refused(self):
        for value in ["b" * 40, "$(touch should-not-exist)", "latest"]:
            self.env["EXPECTED_SOURCE_COMMIT"] = value
            self.assertNotEqual(self.run_guard(), 0)
        self.assertFalse((self.root / "should-not-exist").exists())

    def test_store_tag_needs_exact_source_and_manual_dispatch(self):
        self.env["GITHUB_REF"] = "refs/tags/store-v1.8.8"
        self.assertNotEqual(self.run_guard(), 0)
        self.env["EXPECTED_SOURCE_COMMIT"] = SHA
        self.assertEqual(self.run_guard(), 0)
        self.env["GITHUB_EVENT_NAME"] = "push"
        self.assertNotEqual(self.run_guard(), 0)

    def test_store_tag_cannot_flatten_or_change_the_patch(self):
        self.env["EXPECTED_SOURCE_COMMIT"] = SHA
        for tag in ["store-v1.8.0", "store-v1.8.9"]:
            self.env["GITHUB_REF"] = f"refs/tags/{tag}"
            self.assertNotEqual(self.run_guard(), 0)

    def test_other_repositories_cannot_publish_canonical_snapshots(self):
        self.env["GITHUB_REPOSITORY"] = "someone/mithka"
        self.assertNotEqual(self.run_guard(), 0)


if __name__ == "__main__":
    unittest.main()
