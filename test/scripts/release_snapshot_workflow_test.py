"""Run the workflow's real snapshot/version/tag programs against fake Git."""

import os
import json
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = (ROOT / ".github/workflows/release.yml").read_text()
SOURCE = "a" * 40
CONTROLLER = "b" * 40


def program(name):
    block = re.search(
        r"      - name: "
        + re.escape(name)
        + r"\n.*?        run: \|\n(.*?)(?=\n      - |\n  [a-z]|\Z)",
        WORKFLOW,
        re.S,
    )[1]
    return textwrap.dedent(block)


class ReleaseSnapshotWorkflowTest(unittest.TestCase):
    def test_draft_verification_uses_the_action_release_id_not_published_tag_lookup(
        self,
    ):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "release-assets").mkdir()
            (root / "release-assets/release-manifest.json").write_text(
                '{"files":{"artifact.zip":{"size":100,"sha256":"' + "c" * 64 + '"}}}'
            )
            (root / "bin").mkdir()
            gh = root / "bin/gh"
            gh.write_text("""#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as output:
    output.write(json.dumps(args) + "\\n")
if any("releases/tags/" in value for value in args):
    sys.exit(4) # GitHub's tag endpoint cannot see an unpublished draft.
assert "repos/iebb/mithka/releases/7" in args
if "PATCH" in args:
    payload = json.load(sys.stdin)
    assert payload == {"target_commitish":"master","draft":False,"prerelease":False,"make_latest":"true"}
    print("{}")
else:
    print(json.dumps({"id":7,"tag_name":"v1.8.8","draft":True,"assets":[{"name":"artifact.zip","size":100,"digest":"sha256:"+"c"*64}]}))
""")
            gh.chmod(0o700)
            env = dict(
                os.environ,
                PATH=f"{root / 'bin'}:{os.environ['PATH']}",
                RELEASE_TAG="v1.8.8",
                RELEASE_ID="7",
                CALLS=str(root / "calls"),
            )
            result = subprocess.run(
                ["bash", "-c", program("Verify and publish the store GitHub release")],
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = [
                json.loads(line) for line in (root / "calls").read_text().splitlines()
            ]
            self.assertEqual(len(calls), 2)
            self.assertIn("PATCH", calls[1])

    def run_program(self, name, overrides=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pubspec.yaml").write_text("version: 1.8.8+296\n")
            (root / "android").mkdir()
            (root / "android/version-code.txt").write_text("1000\n")
            (root / "scripts").mkdir()
            (root / "scripts/android-version-code.sh").write_text(
                "cat android/version-code.txt\n"
            )
            (root / "bin").mkdir()
            git = root / "bin/git"
            git.write_text("""#!/bin/bash
printf '%s\\n' "$*" >> "$CALLS"
case "$1" in
 rev-parse)
   if [ "$2" = 'HEAD' ]; then printf '%s\\n' "$FAKE_HEAD"; else printf '%s\\n' "$FAKE_TAG_TARGET"; fi ;;
 ls-remote) exit "$FAKE_TAG_MISSING" ;;
 fetch|config|tag|push) exit 0 ;;
 *) exit 1 ;;
esac
""")
            git.chmod(0o700)
            env = dict(
                os.environ,
                PATH=f"{root / 'bin'}:{os.environ['PATH']}",
                SOURCE_COMMIT=SOURCE,
                STORE_SOURCE_COMMIT=SOURCE,
                GITHUB_SHA=CONTROLLER,
                GITHUB_REF="refs/heads/master",
                GITHUB_REF_NAME="master",
                GITHUB_REPOSITORY="iebb/mithka",
                GITHUB_EVENT_NAME="workflow_dispatch",
                DESKTOP_TEST_ONLY="false",
                GITHUB_OUTPUT=str(root / "output"),
                RELEASE_TAG="v1.8.8",
                CALLS=str(root / "calls"),
                FAKE_HEAD=SOURCE,
                FAKE_TAG_TARGET=SOURCE,
                FAKE_TAG_MISSING="0",
            )
            env.update(overrides or {})
            result = subprocess.run(
                ["bash", "-c", program(name)],
                env=env,
                cwd=root,
                capture_output=True,
                text=True,
            )
            output = (root / "output").read_text() if (root / "output").exists() else ""
            calls = (root / "calls").read_text() if (root / "calls").exists() else ""
            return (
                result.returncode,
                dict(line.split("=", 1) for line in output.splitlines()),
                calls,
            )

    def test_store_snapshot_keeps_the_submitted_patch_and_actual_source_not_controller(
        self,
    ):
        code, output, _calls = self.run_program("Read version from pubspec.yaml")
        self.assertEqual(code, 0)
        self.assertEqual(output["app_version"], "1.8.8")
        self.assertEqual(output["release_tag"], "v1.8.8")
        self.assertEqual(output["prerelease"], "false")
        self.assertEqual(output["short_sha"], SOURCE[:7])
        self.assertEqual(output["android_version_code"], "1000")

    def test_nightly_keeps_its_existing_prerelease_channel(self):
        code, output, _calls = self.run_program(
            "Read version from pubspec.yaml",
            {
                "STORE_SOURCE_COMMIT": "",
                "SOURCE_COMMIT": CONTROLLER,
                "FAKE_HEAD": CONTROLLER,
                "GITHUB_REF": "refs/heads/nightly",
                "GITHUB_REF_NAME": "nightly",
            },
        )
        self.assertEqual(code, 0)
        self.assertTrue(output["release_tag"].startswith("v1.8.8-nightly."))
        self.assertEqual(output["prerelease"], "true")
        self.assertEqual(output["short_sha"], CONTROLLER[:7])

    def test_wrong_checkout_or_nonmaster_store_dispatch_cannot_name_a_release(self):
        for override in [
            {"FAKE_HEAD": CONTROLLER},
            {"GITHUB_REF": "refs/heads/release"},
            {"GITHUB_EVENT_NAME": "push"},
            {"DESKTOP_TEST_ONLY": "true"},
        ]:
            code, output, _calls = self.run_program(
                "Read version from pubspec.yaml", override
            )
            self.assertNotEqual(code, 0)
            self.assertEqual(output, {})

    def test_existing_canonical_tag_is_verified_and_never_moved(self):
        code, _output, calls = self.run_program("Create release tag")
        self.assertEqual(code, 0)
        self.assertNotIn("push ", calls)
        self.assertNotIn("tag -", calls)
        code, _output, calls = self.run_program(
            "Create release tag", {"FAKE_TAG_TARGET": CONTROLLER}
        )
        self.assertNotEqual(code, 0)
        self.assertNotIn("push ", calls)

    def test_missing_store_tag_fails_and_legacy_new_tag_uses_normal_push(self):
        code, _output, calls = self.run_program(
            "Create release tag", {"FAKE_TAG_MISSING": "1"}
        )
        self.assertNotEqual(code, 0)
        self.assertNotIn("push ", calls)
        code, _output, calls = self.run_program(
            "Create release tag",
            {
                "FAKE_TAG_MISSING": "1",
                "STORE_SOURCE_COMMIT": "",
                "SOURCE_COMMIT": CONTROLLER,
                "FAKE_HEAD": CONTROLLER,
            },
        )
        self.assertEqual(code, 0)
        self.assertIn("push origin refs/tags/v1.8.8", calls)
        self.assertNotIn("--force", calls)


if __name__ == "__main__":
    unittest.main()
