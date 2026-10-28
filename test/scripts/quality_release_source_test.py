"""Execute the actual workflow guard with a credential-free GitHub API stand-in."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = (ROOT / ".github/workflows/quality.yml").read_text()
BLOCK = re.search(
    r"      - name: Verify requested release source\n.*?        run: \|\n(.*?)(?=\n      - )",
    WORKFLOW,
    re.S,
)[1]
GUARD = textwrap.dedent(BLOCK)
SOURCE = "a" * 40


class QualityReleaseSourceTest(unittest.TestCase):
    def invoke(self, values=None, merge_base=SOURCE, api_status=0):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "gh"
            seen = Path(directory) / "called"
            executable.write_text(
                "#!/bin/bash\n"
                + 'printf "%s\\n" "$@" > "$GUARD_CALL_PATH"\n'
                + 'printf "%s\\n" "$FAKE_MERGE_BASE"\nexit "$FAKE_API_STATUS"\n'
            )
            executable.chmod(0o700)
            env = dict(
                os.environ,
                PATH=f"{directory}:{os.environ['PATH']}",
                QUALITY_SOURCE_COMMIT=SOURCE,
                GITHUB_REPOSITORY="iebb/mithka",
                GITHUB_EVENT_NAME="workflow_dispatch",
                GITHUB_WORKFLOW="App Store Review Submission",
                GITHUB_REF="refs/heads/master",
                GUARD_CALL_PATH=str(seen),
                FAKE_MERGE_BASE=merge_base,
                FAKE_API_STATUS=str(api_status),
            )
            env.update(values or {})
            result = subprocess.run(
                ["bash", "-c", GUARD], env=env, capture_output=True, text=True
            )
            return result.returncode, seen.read_text() if seen.exists() else None

    def test_normal_pr_and_push_gates_keep_the_event_source_and_make_no_api_override(
        self,
    ):
        for event in ["pull_request", "push", "workflow_dispatch"]:
            status, called = self.invoke(
                {"QUALITY_SOURCE_COMMIT": "", "GITHUB_EVENT_NAME": event}
            )
            self.assertEqual(status, 0)
            self.assertIsNone(called)

    def test_uploaded_ancestor_can_be_checked_even_when_master_has_advanced(self):
        status, called = self.invoke()
        self.assertEqual(status, 0)
        self.assertIn(f"repos/iebb/mithka/compare/{SOURCE}...master", called)
        status, _called = self.invoke({"GITHUB_WORKFLOW": "🚀 Multi-platform Releases"})
        self.assertEqual(status, 0)

    def test_pr_fork_other_caller_or_nonmaster_cannot_override_the_tested_source(self):
        for key, value in [
            ("GITHUB_EVENT_NAME", "pull_request"),
            ("GITHUB_REPOSITORY", "other/mithka"),
            ("GITHUB_WORKFLOW", "Quality"),
            ("GITHUB_REF", "refs/heads/nightly"),
        ]:
            status, called = self.invoke({key: value})
            self.assertNotEqual(status, 0)
            self.assertIsNone(called)

    def test_nonancestor_malformed_sha_and_failed_api_are_rejected(self):
        self.assertNotEqual(self.invoke(merge_base="b" * 40)[0], 0)
        self.assertNotEqual(self.invoke(api_status=1)[0], 0)
        for value in ["master", "abc123", "a" * 39, "a" * 40 + "; exit 0"]:
            status, called = self.invoke({"QUALITY_SOURCE_COMMIT": value})
            self.assertNotEqual(status, 0)
            self.assertIsNone(called)


if __name__ == "__main__":
    unittest.main()
