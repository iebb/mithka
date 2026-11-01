"""Run real review fixtures with inherited CI files and reject output pollution."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReviewOutputTest(unittest.TestCase):
    def test_fixture_reports_and_merge_eligibility_cannot_escape_to_runner_files(self):
        with tempfile.TemporaryDirectory() as directory:
            summary, output = (Path(directory) / name for name in ("summary", "output"))
            summary.write_text("Real workflow summary\n")
            output.write_text("real_step=value\n")
            env = {
                key: value
                for key, value in os.environ.items()
                if key not in ("GH_TOKEN", "GITHUB_TOKEN", "OPENROUTER_API_KEY")
            }
            env.update(GITHUB_STEP_SUMMARY=str(summary), GITHUB_OUTPUT=str(output))
            result = subprocess.run(
                [
                    "node",
                    "--test",
                    "--test-name-pattern",
                    "a fully approved complete PR|quota failure posts",
                    ".github/scripts/pr-review.test.mjs",
                ],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(summary.read_text(), "Real workflow summary\n")
            self.assertEqual(output.read_text(), "real_step=value\n")


if __name__ == "__main__":
    unittest.main()
