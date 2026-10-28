import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]


class SimulatorBuildTests(unittest.TestCase):
    def run_build(self, machine, build_exit=0):
        workflow = (ROOT / ".github/workflows/apple-pr.yml").read_text()
        marker = (
            "      - name: Build the actual iOS app without signing\n        run: |\n"
        )
        self.assertEqual(workflow.count(marker), 1)
        script = textwrap.dedent(
            workflow.split(marker, 1)[1].split("\n      - name:", 1)[0]
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            uname = fake_bin / "uname"
            uname.write_text('#!/bin/sh\nprintf "%s\\n" "$TEST_MACHINE_ARCH"\n')
            uname.chmod(0o755)
            xcodebuild = fake_bin / "xcodebuild"
            xcodebuild.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "with open(os.environ['COMMAND_LOG'], 'w') as output:\n"
                "    json.dump(sys.argv[1:], output)\n"
                "sys.exit(int(os.environ['TEST_BUILD_EXIT']))\n"
            )
            xcodebuild.chmod(0o755)
            command_log = root / "command.json"
            result = subprocess.run(
                ["/bin/bash", "-e", "-c", script],
                cwd=root,
                env={
                    "PATH": f"{fake_bin}{os.pathsep}/usr/bin:/bin",
                    "RUNNER_TEMP": str(root),
                    "TEST_MACHINE_ARCH": machine,
                    "TEST_BUILD_EXIT": str(build_exit),
                    "COMMAND_LOG": str(command_log),
                },
                capture_output=True,
                text=True,
                timeout=10,
            )
            arguments = (
                json.loads(command_log.read_text()) if command_log.exists() else None
            )
            return result, arguments

    def test_build_uses_one_native_simulator_architecture(self):
        for machine in ("arm64", "x86_64"):
            with self.subTest(machine=machine):
                result, arguments = self.run_build(machine)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    [
                        argument
                        for argument in arguments
                        if argument.startswith("ARCHS=")
                    ],
                    [f"ARCHS={machine}"],
                )
                self.assertIn("ONLY_ACTIVE_ARCH=YES", arguments)
                self.assertIn("CODE_SIGNING_ALLOWED=NO", arguments)

    def test_unknown_host_fails_before_building(self):
        result, arguments = self.run_build("unexpected-cpu")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported verification host architecture", result.stderr)
        self.assertIsNone(arguments)

    def test_compiler_failure_still_fails_verification(self):
        result, arguments = self.run_build("arm64", build_exit=42)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNotNone(arguments)


if __name__ == "__main__":
    unittest.main()
